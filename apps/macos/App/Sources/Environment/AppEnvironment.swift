import AppKit
import DocketCore
import DocketGitHub
import DocketNotify
import DocketPersistence
import DocketStores
import DocketUpdate
import Foundation
import Network
import UserNotifications

/// The composition root: the only place that builds adapters (CLAUDE.md, non-negotiable 4).
@MainActor
final class AppEnvironment {
    let configStore: ConfigStore
    let watch: WatchStore
    let poller: Poller
    private let github: GraphQLClient
    let tokens: GhTokenProvider
    let paths: AppPaths
    let permission = NotificationPermission()
    let info = AppInfo(bundle: .main)
    let updates: UpdateStore
    let loginItem = LoginItem()
    private let notifications = UserNotificationSink()
    private var delegate: NotificationDelegate?
    private let monitor = NWPathMonitor()
    private var observers: [NSObjectProtocol] = []

    private var retention: Task<Void, Never>?
    private let storage: FileStores

    init() {
        let paths =
            (try? AppPaths.applicationSupport())
            ?? AppPaths(root: FileManager.default.temporaryDirectory.appending(path: "Docket"))
        self.paths = paths
        let storage = FileStores(paths: paths)
        self.storage = storage
        let configStore = ConfigStore(storage: storage)
        self.configStore = configStore
        watch = WatchStore(configStore: configStore)
        let configuredPath: @Sendable () async -> String? = { await MainActor.run { configStore.config.ghPath } }
        let tokens = GhTokenProvider(configuredPath: configuredPath)
        self.tokens = tokens
        let github = GraphQLClient(tokens: tokens)
        self.github = github
        let poller = Poller(github: github, tokens: tokens, storage: storage, notifications: notifications)
        self.poller = poller
        let bundle = Bundle.main
        let repository =
            bundle.object(forInfoDictionaryKey: "DocketReleaseRepository") as? String ?? "eliasjnior/docket"
        let key = bundle.object(forInfoDictionaryKey: "DocketUpdatePublicKey") as? String
        updates = UpdateStore(
            current: AppInfo(bundle: bundle).semanticVersion,
            // The repository is private, so releases are read with the `gh` token (D-14).
            source: GitHubReleasesSource(repository: repository, token: { try? await tokens.token() }),
            verifier: key.flatMap { try? UpdateVerifier(publicKeyBase64: $0) },
            installer: UpdateInstaller(bundleIdentifier: bundle.bundleIdentifier ?? "com.eliasjnior.docket"),
            runningApp: bundle.bundleURL, configStore: configStore,
            bookkeeping: UpdateStore.Bookkeeping(
                load: {
                    let state = await poller.current().state
                    return (state.lastUpdateCheckAt, state.skippedVersion)
                },
                save: { checked, skipped in
                    await poller.updateState { state in
                        state.lastUpdateCheckAt = checked
                        state.skippedVersion = skipped
                    }
                }))
    }

    /// FR-90: `config.json` and `SMAppService` agree at launch; the user's choice wins.
    func reconcileLoginItem() {
        guard let wanted = configStore.config.launchAtLogin else { return }
        loginItem.refresh()
        if wanted != loginItem.isEnabled { loginItem.setEnabled(wanted) }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginItem.setEnabled(enabled)
        configStore.update { $0.launchAtLogin = enabled }
    }

    /// The version What's New last showed; records the running one. `nil` on a first install.
    func takeLastShownVersion() async -> SemanticVersion? {
        let current = info.semanticVersion.description
        let previous = await poller.current().state.lastShownVersion
        await poller.updateState { $0.lastShownVersion = current }
        return previous.flatMap(SemanticVersion.init)
    }

    /// FR-73: one `repository(owner:, name:)` query.
    func repositoryExists(_ name: String) async -> Bool {
        (try? await github.repositoryExists(name)) ?? false
    }

    /// Clicks on notifications, routed to the app (`docs/02-activity-detection.md` §7.4).
    func handleNotifications(_ route: @escaping @MainActor (NotificationRoute) -> Void) {
        UserNotificationSink.registerCategories()
        let configStore = configStore
        let delegate = NotificationDelegate { click in
            Task { @MainActor in
                switch click {
                case .open(let url): route(.open(url))
                case .popover(let repository): route(.popover(repository: repository))
                case .muteReminders(let id, let ref):
                    configStore.update {
                        $0.mutes[id] = Config.MuteEntry(ref: ref ?? id, scope: .reminders, mutedAt: Date())
                    }
                }
            }
        }
        self.delegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
    }

    func requestNotificationPermission() async {
        permission.status = await notifications.requestAuthorization()
    }

    func refreshNotificationPermission() async {
        permission.status = await notifications.authorization()
    }

    func start() async {
        await configStore.load()
        configStore.onChange = { [weak self] _ in
            Task { await self?.poller.pollNow() }
        }
        let watch = watch
        await poller.start { snapshot in
            await MainActor.run { watch.apply(snapshot) }
        }
        observeSystem()
        startRetention()
    }

    /// Once at launch, after the first poll has a watch set, then daily (`docs/04-data.md` §4).
    private func startRetention() {
        retention = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            while !Task.isCancelled {
                await self?.retainOnce()
                try? await Task.sleep(for: .seconds(86400))
            }
        }
    }

    private func retainOnce() async {
        let pruned = await poller.retain(config: configStore.config) { config, state, watched, now in
            let result = Retention.apply(config: config, state: state, watched: watched, now: now)
            return (result.config, result.state)
        }
        configStore.update { config in
            config.mutes = pruned.mutes
            config.ignored = pruned.ignored
        }
        await storage.pruneCorruptFiles(now: Date())
    }

    /// `Try Again` on an account screen: forget the `gh` lookup and poll (`docs/05-design.md` §7.1).
    func retryAuthentication() {
        Task {
            await tokens.reset()
            await poller.pollNow()
        }
    }

    private func observeSystem() {
        let center = NSWorkspace.shared.notificationCenter
        let poller = poller
        observers.append(
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
                Task { await poller.willSleep() }
            })
        observers.append(
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                Task { await poller.didWake() }
            })
        monitor.pathUpdateHandler = { path in
            Task { await poller.setOnline(path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "com.eliasjnior.docket.network"))
    }
}

/// Where a notification click leads, in the app's terms.
enum NotificationRoute {
    case open(URL)
    case popover(repository: String?)
}

/// Notification permission as settings and the banner show it.
@MainActor
@Observable
final class NotificationPermission {
    var status: NotificationAuthorization = .notAsked
}
