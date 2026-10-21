import AppKit
import DocketCore
import DocketGitHub
import DocketPersistence
import DocketStores
import Foundation
import Network

/// The composition root: the only place that builds adapters (CLAUDE.md, non-negotiable 4).
@MainActor
final class AppEnvironment {
    let configStore: ConfigStore
    let watch: WatchStore
    let poller: Poller
    let tokens: GhTokenProvider
    let paths: AppPaths
    private let monitor = NWPathMonitor()
    private var observers: [NSObjectProtocol] = []

    init(notifications: NotificationSink) {
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
