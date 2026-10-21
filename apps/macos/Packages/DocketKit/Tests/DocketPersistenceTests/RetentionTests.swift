import DocketCore
import Foundation
import Testing

@testable import DocketPersistence

struct RetentionTests {
    private let now = Date(timeIntervalSince1970: 1_792_584_000)
    private let day: TimeInterval = 86400

    @Test func everyRowOfTheRetentionTable() {
        let cursor = { (leftDays: Double?) in
            Cursor(
                ref: "acme/api#1", role: leftDays == nil ? .authored : nil, updatedAt: self.now, enteredAt: self.now,
                leftAt: leftDays.map { self.now.addingTimeInterval(-$0 * self.day) })
        }
        let state = PersistedState(
            cursors: ["PR_WATCHED": cursor(nil), "PR_LEFT_RECENTLY": cursor(29), "PR_LEFT_LONG_AGO": cursor(31)],
            delivered: ["old": now.addingTimeInterval(-15 * day), "recent": now.addingTimeInterval(-day)],
            marked: ["PR_WATCHED", "PR_LEFT_RECENTLY"],
            teams: [
                "acme": TeamCache(slugs: ["backend"], fetchedAt: now.addingTimeInterval(-day)),
                "gone": TeamCache(slugs: ["x"], fetchedAt: now.addingTimeInterval(-31 * day)),
            ])
        var config = Config()
        for id in ["PR_WATCHED", "PR_LEFT_RECENTLY", "PR_LEFT_LONG_AGO", "PR_UNKNOWN"] {
            config.tags[id] = Config.TagEntry(ref: id, tags: ["wip"], updatedAt: now)
            config.mutes[id] = Config.MuteEntry(ref: id, scope: .all, mutedAt: now)
            config.ignored[id] = Config.IgnoreEntry(ref: id, ignoredAt: now)
        }
        let result = Retention.apply(config: config, state: state, watched: ["PR_WATCHED"], now: now)
        #expect(result.state.cursors.keys.sorted() == ["PR_LEFT_RECENTLY", "PR_WATCHED"])
        #expect(result.state.delivered.keys.sorted() == ["recent"])
        #expect(result.state.marked == ["PR_WATCHED"])
        #expect(result.state.teams.keys.sorted() == ["acme"])
        #expect(result.config.tags.keys.sorted() == ["PR_LEFT_RECENTLY", "PR_WATCHED"])
        #expect(result.config.mutes.keys.sorted() == ["PR_LEFT_RECENTLY", "PR_WATCHED"])
        #expect(result.config.ignored.keys.sorted() == ["PR_LEFT_RECENTLY", "PR_WATCHED"])
    }

    @Test func corruptFilesExpireAfterSevenDays() async throws {
        let names = [
            "state.corrupt-20261013T120000Z.json", "state.corrupt-20261020T120000Z.json", "state.json",
            "x.corrupt-bad.json",
        ]
        #expect(Retention.expiredCorruptFiles(names, now: now) == ["state.corrupt-20261013T120000Z.json"])
        let root = FileManager.default.temporaryDirectory.appending(path: "docket-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in names { try Data().write(to: root.appending(path: name)) }
        await FileStores(paths: AppPaths(root: root)).pruneCorruptFiles(now: now)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
                == names.filter { $0 != names[0] }.sorted())
    }
}
