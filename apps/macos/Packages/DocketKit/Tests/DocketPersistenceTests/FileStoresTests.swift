import DocketCore
import Foundation
import Testing

@testable import DocketPersistence

struct FileStoresTests {
    private let root: URL
    private let stores: FileStores
    private let now = Date(timeIntervalSince1970: 1_792_584_000)

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "docket-\(UUID().uuidString)")
        stores = FileStores(paths: AppPaths(root: root), now: { Date(timeIntervalSince1970: 1_792_584_000) })
    }

    private func permissions(_ url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }

    @Test func aFirstLaunchHasDefaultsAndNoState() async throws {
        #expect(try await stores.loadConfig() == Config())
        #expect(try await stores.loadState() == nil)
        #expect(await stores.loadCache() == nil)
    }

    @Test func writeThenReadIsTheIdentity() async throws {
        var config = Config()
        config.tags["PR_1"] = Config.TagEntry(ref: "acme/api#482", tags: ["wip"], updatedAt: now)
        let state = PersistedState(viewerLogin: "you", baselineAt: now, delivered: ["reviewRequested:E1": now])
        let cache = SnapshotCache(fetchedAt: now, viewerLogin: "you")
        try await stores.saveConfig(config)
        try await stores.saveState(state)
        try await stores.saveCache(cache)
        #expect(try await stores.loadConfig() == config)
        #expect(try await stores.loadState() == state)
        #expect(await stores.loadCache() == cache)
    }

    @Test func filesAreOwnerOnly() async throws {
        try await stores.saveState(PersistedState())
        try await stores.saveCache(SnapshotCache(fetchedAt: now, viewerLogin: "you"))
        let paths = AppPaths(root: root)
        #expect(try permissions(root) == 0o700)
        #expect(try permissions(paths.state) == 0o600)
        #expect(try permissions(paths.snapshot) == 0o600)
        #expect(try paths.cache.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func filesAreSortedAndReadable() async throws {
        try await stores.saveConfig(Config())
        let text = try String(contentsOf: AppPaths(root: root).config, encoding: .utf8)
        #expect(text.contains("\"botAllowlist\" : ["))
        #expect(
            try #require(text.range(of: "botAllowlist")).lowerBound < #require(text.range(of: "version")).lowerBound)
    }

    @Test func anUnreadableStateIsSetAsideForAFreshBaseline() async throws {
        let paths = AppPaths(root: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: paths.state)
        #expect(try await stores.loadState() == nil)
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(names.contains("state.corrupt-20261021T120000Z.json"))
        #expect(!names.contains("state.json"))
    }

    @Test func aNewerFileIsNeverOverwritten() async throws {
        let paths = AppPaths(root: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let newer = Data(#"{ "version": 9, "future": true }"#.utf8)
        try newer.write(to: paths.state)
        try newer.write(to: paths.config)
        await #expect(throws: PersistenceError.newerVersion(file: "state.json", version: 9)) {
            try await stores.loadState()
        }
        await #expect(throws: PersistenceError.self) { try await stores.saveState(PersistedState()) }
        await #expect(throws: PersistenceError.newerVersion(file: "config.json", version: 9)) {
            try await stores.loadConfig()
        }
        await #expect(throws: PersistenceError.self) { try await stores.saveConfig(Config()) }
        #expect(try Data(contentsOf: paths.state) == newer)
        #expect(try Data(contentsOf: paths.config) == newer)
    }

    @Test func aTruncatedCacheIsIgnored() async throws {
        let paths = AppPaths(root: root)
        try FileManager.default.createDirectory(at: paths.cache, withIntermediateDirectories: true)
        try Data(#"{ "version": 1, "fetchedAt": "#.utf8).write(to: paths.snapshot)
        #expect(await stores.loadCache() == nil)
    }

    @Test func anUnwritableLocationIsTyped() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: AppPaths(root: root).state, withIntermediateDirectories: true)
        await #expect(throws: PersistenceError.unwritable(file: "state.json")) {
            try await stores.saveState(PersistedState())
        }
    }

    @Test func applicationSupportIsTheDocketFolder() throws {
        #expect(try AppPaths.applicationSupport().root.lastPathComponent == "Docket")
    }
}
