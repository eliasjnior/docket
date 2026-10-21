import DocketCore
import DocketPersistence
import DocketStores
import DocketUpdate
import Foundation
import Synchronization
import Testing

/// A release source answering from a script; the network edge itself is covered in `DocketUpdateTests`.
struct ScriptedReleases: ReleaseSource {
    var update: AvailableUpdate?
    var error: UpdateError?

    func latest(after current: SemanticVersion) async throws -> AvailableUpdate? {
        if let error { throw error }
        return update.flatMap { $0.version > current ? $0 : nil }
    }

    func downloadArchive(of update: AvailableUpdate, to directory: URL) async throws -> URL {
        throw UpdateError.installFailed("not in tests")
    }
}

@MainActor
struct UpdateStoreTests {
    private func update(_ version: String) throws -> AvailableUpdate {
        let fields = #""build":"1","asset":"Docket.zip","signature":"","size":1,"minimumSystemVersion":"15.0""#
        let json = #"{"version":"\#(version)","# + fields + "}"
        let manifest = try JSONDecoder().decode(ReleaseManifest.self, from: Data(json.utf8))
        return AvailableUpdate(
            version: try #require(SemanticVersion(version)), notes: "", publishedAt: nil, manifest: manifest,
            archiveURL: try #require(URL(string: "https://api.test/a")))
    }

    private func store(_ source: ScriptedReleases, saved: Saved = Saved()) -> UpdateStore {
        let files = FileStores(
            paths: AppPaths(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)))
        let record = saved
        return UpdateStore(
            current: SemanticVersion(major: 1, minor: 0, patch: 0), source: source, verifier: nil,
            installer: UpdateInstaller(bundleIdentifier: "com.eliasjnior.docket"),
            runningApp: URL(fileURLWithPath: "/Applications/Docket.app"), configStore: ConfigStore(storage: files),
            bookkeeping: UpdateStore.Bookkeeping(load: { (nil, nil) }, save: { _, skipped in record.append(skipped) }))
    }

    @Test func aNewerReleaseIsAvailableAndCanBeSkipped() async throws {
        let saved = Saved()
        let store = store(ScriptedReleases(update: try update("1.1.0")), saved: saved)
        await store.check(userInitiated: false)
        #expect(store.availableUpdate?.version.description == "1.1.0")
        store.skip(try #require(store.availableUpdate))
        #expect(store.phase == .upToDate)
        await store.check(userInitiated: false)
        #expect(store.phase == .upToDate)
        await store.check(userInitiated: true)
        #expect(store.availableUpdate != nil)
        try await Task.sleep(for: .milliseconds(20))
        #expect(saved.all.contains("1.1.0"))
    }

    @Test func upToDateAndErrors() async throws {
        let current = store(ScriptedReleases(update: try update("1.0.0")))
        await current.check(userInitiated: true)
        #expect(current.phase == .upToDate)
        #expect(current.lastChecked != nil)
        let refused = store(ScriptedReleases(error: .unauthorized))
        await refused.check(userInitiated: true)
        if case .failed = refused.phase {} else { Issue.record("expected failure") }
    }

    @Test func installingWithoutAKeyFails() async throws {
        let store = store(ScriptedReleases(update: try update("1.1.0")))
        await store.install(try update("1.1.0"))
        if case .failed = store.phase {} else { Issue.record("expected failure") }
    }
}

final class Saved: Sendable {
    private let values = Mutex<[String?]>([])
    func append(_ value: String?) { values.withLock { $0.append(value) } }
    var all: [String?] { values.withLock { $0 } }
}
