import AppKit
import DocketCore
import DocketGitHub
import DocketNotify
import DocketPersistence
import DocketStores
import Foundation
import Network
import UserNotifications

/// The composition root: the only place that builds adapters (CLAUDE.md, non-negotiable 4).
@MainActor
final class AppEnvironment {
    let configStore: ConfigStore
    let watch: WatchStore
    let poller: Poller
    let tokens: GhTokenProvider
    let paths: AppPaths
    let permission = NotificationPermission()
    private let notifications = UserNotificationSink()
    private var delegate: NotificationDelegate?
    private let monitor = NWPathMonitor()
    private var observers: [NSObjectProtocol] = []

    init() {
        let paths =
            (try? AppPaths.applicationSupport())
            ?? AppPaths(root: FileManager.default.temporaryDirectory.appending(path: "Docket"))
        self.paths = paths
        let storage = FileStores(paths: paths)
        let configStore = ConfigStore(storage: storage)
        self.configStore = configStore
        watch = WatchStore(configStore: configStore)
        let configuredPath: @Sendable () async -> String? = { await MainActor.run { configStore.config.ghPath } }
        let tokens = GhTokenProvider(configuredPath: configuredPath)
        self.tokens = tokens
        poller = Poller(
            github: GraphQLClient(tokens: tokens), tokens: tokens, storage: storage, notifications: notifications)
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
