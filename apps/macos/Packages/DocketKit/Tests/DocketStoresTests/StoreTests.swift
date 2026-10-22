import DocketCore
import DocketPersistence
import DocketStores
import DocketTestSupport
import Foundation
import Testing

@MainActor
struct StoreTests {
    private let now = Fixtures.now

    private func storage() -> FileStores {
        FileStores(
            paths: AppPaths(root: FileManager.default.temporaryDirectory.appending(path: "docket-\(UUID().uuidString)"))
        )
    }

    @Test func configChangesAreSavedAndAnnounced() async throws {
        let files = storage()
        let store = ConfigStore(storage: files)
        await store.load()
        var announced: [Int] = []
        store.onChange = { announced.append($0.polling.intervalSeconds) }
        store.update { $0.polling.intervalSeconds = 120 }
        store.update { $0.polling.intervalSeconds = 120 }
        #expect(announced == [120])
        try await Task.sleep(for: .milliseconds(50))
        #expect(try await files.loadConfig().polling.intervalSeconds == 120)
    }

    @Test func aNewerConfigIsReadOnly() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "docket-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(#"{"version": 5}"#.utf8).write(to: AppPaths(root: root).config)
        let store = ConfigStore(storage: FileStores(paths: AppPaths(root: root)))
        await store.load()
        #expect(store.isReadOnly)
        store.update { $0.polling.intervalSeconds = 30 }
        #expect(store.config.polling.intervalSeconds == 60)
    }

    @Test func theWatchStoreDerivesRowsCountAndStaleness() {
        let configStore = ConfigStore(storage: storage())
        let store = WatchStore(configStore: configStore)
        let requested = CachedPullRequest(
            pullRequest: Fixtures.pullRequest("PR_1", requests: [.user(login: "you")]), role: .reviewRequested)
        let mine = CachedPullRequest(
            pullRequest: Fixtures.pullRequest("PR_2", author: "you", checks: .failure), role: .authored)
        store.apply(
            WatchSnapshot(
                cache: SnapshotCache(
                    fetchedAt: now, viewerLogin: "you", pullRequests: [requested, mine], notShown: ["requested": 4]),
                account: .ready))
        #expect(store.count == 2)
        #expect(store.sections().mine.map(\.id) == ["PR_2"])
        #expect(store.notShown(.reviewRequested) == 4)
        #expect(!store.isStale(now: now.addingTimeInterval(120)))
        #expect(store.isStale(now: now.addingTimeInterval(121)))
        configStore.update { $0.count.includeReviewRequests = false }
        #expect(store.count == 1)
    }
}
