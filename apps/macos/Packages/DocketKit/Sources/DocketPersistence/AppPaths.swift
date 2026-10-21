import Foundation

/// The three locations under `~/Library/Application Support/Docket/` (`docs/04-data.md`).
public struct AppPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static func applicationSupport() throws -> AppPaths {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return AppPaths(root: base.appending(path: "Docket", directoryHint: .isDirectory))
    }

    public var config: URL { root.appending(path: "config.json") }
    public var state: URL { root.appending(path: "state.json") }
    public var cache: URL { root.appending(path: "cache", directoryHint: .isDirectory) }
    public var snapshot: URL { cache.appending(path: "snapshot.json") }
}
