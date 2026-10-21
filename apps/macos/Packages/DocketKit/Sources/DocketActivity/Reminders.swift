import DocketCore
import Foundation

/// Reminders of review requests still pending (`docs/02-activity-detection.md` §5.7).
public enum Reminders {
    /// Whether `now` falls inside the quiet hours, in `timeZone`; the window may cross midnight.
    public static func inQuietHours(_ now: Date, _ quietHours: Config.QuietHours, timeZone: TimeZone) -> Bool {
        guard quietHours.enabled, let start = minutes(quietHours.start), let end = minutes(quietHours.end),
            start != end
        else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let local = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return start < end ? (start <= local && local < end) : (local >= start || local < end)
    }

    /// `HH:mm` as minutes after midnight.
    public static func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]), (0..<24).contains(hour),
            (0..<60).contains(minute)
        else { return nil }
        return hour * 60 + minute
    }

    /// Whether a watched pull request is pending: requested from you, not a draft, neither muted nor ignored.
    public static func isPending(_ entry: CachedPullRequest, config: Config) -> Bool {
        entry.role == .reviewRequested && !entry.pullRequest.isDraft && config.mutes[entry.id] == nil
            && config.ignored[entry.id] == nil
    }

    public struct Context {
        public var now: Date
        public var timeZone: TimeZone
        public var config: Config
        /// The first poll of a fresh install.
        public var isBaseline: Bool
        /// Pull requests whose `reviewRequested` event is new in this poll.
        public var newlyRequested: Set<String>
        public var holding: Bool

        public init(
            now: Date, timeZone: TimeZone, config: Config, isBaseline: Bool, newlyRequested: Set<String>,
            holding: Bool = false
        ) {
            self.now = now
            self.timeZone = timeZone
            self.config = config
            self.isBaseline = isBaseline
            self.newlyRequested = newlyRequested
            self.holding = holding
        }
    }

    /// Updates the records for this poll's watch set and returns the reminders due now.
    public static func due(
        _ watched: [CachedPullRequest], records: inout [String: ReminderRecord], context: Context
    ) -> [Reminder] {
        let now = context.now
        let settings = context.config.reminders
        var next: [String: ReminderRecord] = [:]
        var due: [Reminder] = []
        let quiet = inQuietHours(now, settings.quietHours, timeZone: context.timeZone)
        for entry in watched where isPending(entry, config: context.config) {
            let requestedAt = entry.request?.requestedAt ?? entry.pullRequest.createdAt
            var record: ReminderRecord
            if context.newlyRequested.contains(entry.id), records[entry.id]?.requestedAt != requestedAt {
                // The request notifies now, and that notification is the first notice.
                record = ReminderRecord(requestedAt: requestedAt, lastRemindedAt: now)
            } else if let existing = records[entry.id], existing.requestedAt == requestedAt {
                record = existing
            } else if records[entry.id] != nil {
                // A re-request whose event was not seen: anchor on the request itself.
                record = ReminderRecord(requestedAt: requestedAt, lastRemindedAt: nil)
            } else {
                // Seen for the first time without being new (baseline, re-included, team learned): no burst.
                record = ReminderRecord(requestedAt: requestedAt, lastRemindedAt: now)
            }
            let anchor = record.lastRemindedAt ?? record.requestedAt
            if settings.enabled, !quiet, !context.holding, now >= anchor.addingTimeInterval(settings.interval) {
                due.append(
                    Reminder(
                        pullRequestID: entry.id, repository: entry.pullRequest.repository,
                        number: entry.pullRequest.number, title: entry.pullRequest.title, url: entry.pullRequest.url,
                        requestedAt: requestedAt, requestedBy: entry.request?.requestedBy, at: now))
                record.lastRemindedAt = now
            }
            next[entry.id] = record
        }
        records = next
        return due
    }
}
