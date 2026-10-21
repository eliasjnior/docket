import Foundation

public protocol ConfigStoring: Sendable {
    func loadConfig() async throws -> Config
    func saveConfig(_ config: Config) async throws
}

public protocol StateStoring: Sendable {
    /// `nil` on a first launch, or after an unreadable file was set aside.
    func loadState() async throws -> PersistedState?
    func saveState(_ state: PersistedState) async throws
}

public protocol CacheStoring: Sendable {
    func loadCache() async -> SnapshotCache?
    func saveCache(_ cache: SnapshotCache) async throws
}

public enum PersistenceError: Error, Hashable, Sendable {
    /// The file was written by a newer Docket; it is left untouched and not overwritten (`docs/04-data.md` §1).
    case newerVersion(file: String, version: Int)
    case unwritable(file: String)
}
