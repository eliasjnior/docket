import DocketCore
import Foundation

/// What is deleted when (`docs/04-data.md` §4), as a pure function over the files and `now`.
public enum Retention {
    public static let cursorDays: TimeInterval = 30 * 86400
    public static let teamDays: TimeInterval = 30 * 86400
    public static let corruptDays: TimeInterval = 7 * 86400

    public struct Result: Hashable, Sendable {
        public var config: Config
        public var state: PersistedState
    }

    public static func apply(config: Config, state: PersistedState, watched: Set<String>, now: Date) -> Result {
        var state = state
        state.cursors = state.cursors.filter { _, cursor in
            guard let leftAt = cursor.leftAt else { return true }
            return now.timeIntervalSince(leftAt) <= cursorDays
        }
        state.teams = state.teams.filter { now.timeIntervalSince($0.value.fetchedAt) <= teamDays }
        state.delivered = state.delivered.filter { now.timeIntervalSince($0.value) <= 14 * 86400 }
        state.marked.removeAll { !watched.contains($0) }
        // A mute or ignore lives while its pull request has a role or a cursor.
        let alive = Set(state.cursors.keys).union(watched)
        state.seen = state.seen.filter { alive.contains($0.key) }
        var config = config
        config.mutes = config.mutes.filter { alive.contains($0.key) }
        config.ignored = config.ignored.filter { alive.contains($0.key) }
        return Result(config: config, state: state)
    }

    /// `state.corrupt-<timestamp>.json` files older than 7 days, by their timestamp.
    public static func expiredCorruptFiles(_ names: [String], now: Date) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return names.filter { name in
            guard let range = name.range(of: ".corrupt-"), name.hasSuffix(".json") else { return false }
            let stamp = name[range.upperBound...].dropLast(".json".count)
            guard let date = formatter.date(from: String(stamp)) else { return false }
            return now.timeIntervalSince(date) > corruptDays
        }
    }
}

extension FileStores {
    /// Deletes set-aside files past their retention.
    public func pruneCorruptFiles(now: Date) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: paths.root.path)) ?? []
        for name in Retention.expiredCorruptFiles(names, now: now) {
            try? FileManager.default.removeItem(at: paths.root.appending(path: name))
        }
    }
}
