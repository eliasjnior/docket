import DocketCore
import DocketGitHub
import DocketPersistence
import DocketStores
import DocketTestSupport
import Foundation
import Synchronization

extension ManualClock: Clock {}

/// Answers `gh auth token` with a scripted result.
final class TokenRunner: CommandRunner {
    private let result = Mutex(CommandResult(status: 0, output: "gho_synthetic\n"))
    private let found: Bool

    init(found: Bool = true) {
        self.found = found
    }

    func set(_ result: CommandResult) {
        self.result.withLock { $0 = result }
    }

    func isExecutable(_ path: String) -> Bool { found && path == "/opt/homebrew/bin/gh" }

    func run(_ executable: String, _ arguments: [String], environment: [String: String], timeout: TimeInterval)
        async throws -> CommandResult
    {
        guard found else { throw CommandError.notExecutable }
        return result.withLock { $0 }
    }
}

/// The stores composed as `AppEnvironment` composes them, with stubs only at the edges: the network
/// (`GitHubURLProtocol`), the `gh` process (`TokenRunner`), Notification Center and the clock.
struct Harness {
    let root: URL
    let clock = ManualClock()
    let sink = RecordingNotificationSink()
    let runner: TokenRunner
    let storage: FileStores
    let poller: Poller
    let published = Published()

    init(world: GitHubWorld, root: URL? = nil, ghFound: Bool = true) {
        GitHubWorld.set(world)
        self.root = root ?? FileManager.default.temporaryDirectory.appending(path: "docket-\(UUID().uuidString)")
        runner = TokenRunner(found: ghFound)
        storage = FileStores(paths: AppPaths(root: self.root))
        let tokens = GhTokenProvider(runner: runner)
        let github = GraphQLClient(
            tokens: tokens, session: GraphQLClient.makeSession(protocolClasses: [GitHubURLProtocol.self]))
        let clock = self.clock
        poller = Poller(
            github: github, tokens: tokens, storage: storage, notifications: sink, clock: clock,
            timeZone: { TimeZone(identifier: "America/Sao_Paulo") ?? .current }, jitter: { 1 })
    }

    /// A second launch over the same folder.
    func relaunch(world: GitHubWorld? = nil) -> Harness {
        let next = Harness(world: world ?? GitHubWorldSnapshot.current, root: root)
        next.clock.set(clock.now())
        return next
    }

    func poll() async -> WatchSnapshot {
        await poller.pollNow()
        return await poller.current()
    }

    func state() async -> PersistedState? { try? await storage.loadState() }
}

enum GitHubWorldSnapshot {
    static var current: GitHubWorld {
        var world = GitHubWorld()
        GitHubWorld.update { world = $0 }
        return world
    }
}

/// What the poller published, in order.
final class Published: Sendable {
    private let snapshots = Mutex<[WatchSnapshot]>([])

    func append(_ snapshot: WatchSnapshot) { snapshots.withLock { $0.append(snapshot) } }
    var all: [WatchSnapshot] { snapshots.withLock { $0 } }
}
