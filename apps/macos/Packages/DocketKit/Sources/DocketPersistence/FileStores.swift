import DocketCore
import Foundation

/// `config.json`, `state.json` and `cache/snapshot.json`, written only here (`docs/04-data.md`).
public actor FileStores: ConfigStoring, StateStoring, CacheStoring {
    public let paths: AppPaths
    private let config: VersionedFile<Config>
    private let state: VersionedFile<PersistedState>
    private let cache: VersionedFile<SnapshotCache>
    /// Files from a newer Docket: never overwritten while this version runs.
    private var readOnly: Set<String> = []

    public init(paths: AppPaths, now: @escaping @Sendable () -> Date = { Date() }) {
        self.paths = paths
        config = VersionedFile(url: paths.config, currentVersion: Config.currentVersion, now: now)
        state = VersionedFile(url: paths.state, currentVersion: PersistedState.currentVersion, now: now)
        cache = VersionedFile(url: paths.snapshot, currentVersion: SnapshotCache.currentVersion, now: now)
    }

    public func loadConfig() throws -> Config {
        switch config.load() {
        case .value(let value): return value
        case .missing, .corrupt: return Config()
        case .newer(let version):
            readOnly.insert(paths.config.lastPathComponent)
            throw PersistenceError.newerVersion(file: paths.config.lastPathComponent, version: version)
        }
    }

    public func saveConfig(_ value: Config) throws {
        try ensureWritable(paths.config)
        try config.save(value)
    }

    public func loadState() throws -> PersistedState? {
        switch state.load() {
        case .value(let value): return value
        case .missing, .corrupt: return nil
        case .newer(let version):
            readOnly.insert(paths.state.lastPathComponent)
            throw PersistenceError.newerVersion(file: paths.state.lastPathComponent, version: version)
        }
    }

    public func saveState(_ value: PersistedState) throws {
        try ensureWritable(paths.state)
        try state.save(value)
    }

    public func loadCache() -> SnapshotCache? {
        if case .value(let value) = cache.load() { return value }
        return nil
    }

    public func saveCache(_ value: SnapshotCache) throws {
        try cache.save(value)
        var directory = paths.cache
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
    }

    private func ensureWritable(_ url: URL) throws {
        if readOnly.contains(url.lastPathComponent) {
            throw PersistenceError.newerVersion(file: url.lastPathComponent, version: Int.max)
        }
    }
}
