import DocketCore
import Foundation

/// A planned notification worded for Notification Center (`docs/02-activity-detection.md` §7.1,
/// `docs/05-design.md` §8). Pure, so the copy is tested without Notification Center.
public struct ComposedNotification: Hashable, Sendable {
    public enum Category: String, Sendable {
        case single = "docket.single"
        case group = "docket.group"
        case reminder = "docket.reminder"
        case digest = "docket.digest"
    }

    public var identifier: String
    public var title: String
    public var subtitle: String
    public var body: String
    public var category: Category
    /// `repo:<owner/name>`, so macOS stacks one repository together (FR-54).
    public var threadIdentifier: String
    public var repository: String?
    /// What a click opens (§7.4); `nil` opens the popover filtered to `repository`.
    public var url: URL?
    /// For `Mute Reminders` on a single reminder.
    public var pullRequestID: String?

    public static let titleLimit = 80
    public static let bodyLineLimit = 4

    public init(_ planned: PlannedNotification, now: Date) {
        repository = planned.repository
        threadIdentifier = planned.repository.map { "repo:\($0)" } ?? "docket"
        identifier = planned.deliveredIDs.first ?? "overflow:\(now.timeIntervalSince1970)"
        subtitle = ""
        body = ""
        title = ""
        category = .group
        switch planned.content {
        case .events(let kind, let events):
            if events.count == 1, let event = events.first {
                single(kind, event)
            } else {
                group(kind, events)
            }
        case .reminders(let reminders):
            remind(reminders, now: now)
        case .overflow(let updates, let repositories):
            title = String(
                localized: "\(updates) more updates in \(repositories) repositories",
                comment: "The fifth notification when a poll has more than five")
            category = .group
        case .digest(let held):
            digest(held)
        }
    }

    private mutating func single(_ kind: EventKind, _ event: Event) {
        let actor = "@\(event.actor ?? "")"
        subtitle = "\(event.repository) #\(event.number)"
        body = Self.truncated(event.title)
        category = .single
        url = event.url
        switch kind {
        case .reviewRequested:
            title = String(localized: "Review requested by \(actor)", comment: "One review request")
            if let team = event.team {
                body += " · " + String(localized: "via \(team.handle)", comment: "Team request")
            }
        case .reviewSubmitted:
            title = Self.decision(actor, event.decision)
        case .threadReply:
            title = String(localized: "\(actor) replied to your comment", comment: "One reply")
        case .commentAdded:
            title = String(localized: "\(actor) commented", comment: "One comment on your pull request")
        case .checksFailed:
            title = String(localized: "Checks failed", comment: "Checks failed on your pull request")
        case .closedByOther:
            title =
                event.decision == .approved
                ? String(localized: "\(actor) merged your pull request", comment: "Merged by someone else")
                : String(localized: "\(actor) closed your pull request", comment: "Closed by someone else")
        case .mention:
            title = String(localized: "\(actor) mentioned you", comment: "One mention")
        }
    }

    private mutating func group(_ kind: EventKind, _ events: [Event]) {
        let count = events.count
        subtitle = events.first?.repository ?? ""
        category = .group
        let lines: [String]
        switch kind {
        case .reviewRequested:
            title = String(localized: "\(count) reviews requested", comment: "Several review requests")
            lines = events.map { "#\($0.number) \(Self.truncated($0.title))" }
        case .reviewSubmitted:
            title = String(localized: "\(count) reviews on your pull requests", comment: "Several reviews")
            lines = events.map { Self.decision("@\($0.actor ?? "")", $0.decision) + " #\($0.number)" }
        case .threadReply:
            title = String(localized: "\(count) replies to your comments", comment: "Several replies")
            lines = events.map { String(localized: "@\($0.actor ?? "") on #\($0.number)", comment: "Reply line") }
        case .commentAdded:
            title = String(localized: "\(count) comments on your pull requests", comment: "Several comments")
            lines = events.map { String(localized: "@\($0.actor ?? "") on #\($0.number)", comment: "Comment line") }
        case .checksFailed:
            title = String(localized: "Checks failed on \(count) pull requests", comment: "Several failing checks")
            lines = events.map { "#\($0.number) \(Self.truncated($0.title))" }
        case .closedByOther:
            title = String(localized: "\(count) pull requests closed", comment: "Several closed by others")
            lines = events.map { "#\($0.number) \(Self.truncated($0.title))" }
        case .mention:
            title = String(localized: "\(count) mentions", comment: "Several mentions")
            lines = events.map { String(localized: "@\($0.actor ?? "") on #\($0.number)", comment: "Mention line") }
        }
        body = Self.lines(lines)
    }

    private mutating func remind(_ reminders: [Reminder], now: Date) {
        guard let first = reminders.first else { return }
        if reminders.count == 1 {
            title = String(localized: "Your review is still waiting", comment: "One reminder")
            subtitle = "\(first.repository) #\(first.number)"
            let ago = Self.ago(now.timeIntervalSince(first.requestedAt))
            let by = first.requestedBy.map { " " + String(localized: "by @\($0)", comment: "Reminder requester") } ?? ""
            body =
                Self.truncated(first.title) + " · " + String(localized: "requested \(ago) ago", comment: "Reminder")
                + by
            category = .reminder
            url = first.url
            pullRequestID = first.pullRequestID
        } else {
            title = String(localized: "\(reminders.count) reviews still waiting for you", comment: "Several reminders")
            subtitle = first.repository
            body = Self.lines(
                reminders.map {
                    "#\($0.number) \(Self.truncated($0.title)) · \(Self.ago(now.timeIntervalSince($0.requestedAt)))"
                })
            category = .group
        }
    }

    private mutating func digest(_ held: [HeldEvent]) {
        title = String(localized: "While you were in Focus", comment: "The Focus digest")
        subtitle = held.first?.repository ?? ""
        category = .digest
        var lines: [String] = []
        for kind in [
            EventKind.reviewRequested, .reviewSubmitted, .threadReply, .commentAdded, .checksFailed, .closedByOther,
            .mention,
        ] {
            let ofKind = held.filter { $0.kind == kind }
            guard !ofKind.isEmpty else { continue }
            if kind == .reviewSubmitted, ofKind.count == 1, let one = ofKind.first {
                lines.append(Self.decision("@\(one.actor ?? "")", one.decision) + " #\(one.number)")
                continue
            }
            lines.append(Self.digestLine(kind, count: ofKind.count))
        }
        body = Self.lines(lines)
    }

    static func digestLine(_ kind: EventKind, count: Int) -> String {
        switch kind {
        case .reviewRequested: String(localized: "\(count) reviews requested", comment: "Digest line")
        case .reviewSubmitted: String(localized: "\(count) reviews on your pull requests", comment: "Digest line")
        case .threadReply: String(localized: "\(count) replies to your comments", comment: "Digest line")
        case .commentAdded: String(localized: "\(count) comments on your pull requests", comment: "Digest line")
        case .checksFailed: String(localized: "Checks failed on \(count) pull requests", comment: "Digest line")
        case .closedByOther: String(localized: "\(count) pull requests closed", comment: "Digest line")
        case .mention: String(localized: "\(count) mentions", comment: "Digest line")
        }
    }

    static func decision(_ actor: String, _ decision: ReviewState?) -> String {
        switch decision {
        case .approved: String(localized: "\(actor) approved", comment: "Review decision")
        case .changesRequested: String(localized: "\(actor) requested changes", comment: "Review decision")
        default: String(localized: "\(actor) commented", comment: "Review decision")
        }
    }

    /// At most four lines; more end with `and N more`.
    static func lines(_ lines: [String]) -> String {
        guard lines.count > bodyLineLimit else { return lines.joined(separator: "\n") }
        let shown = lines.prefix(bodyLineLimit - 1)
        let more = String(localized: "and \(lines.count - shown.count) more", comment: "Last body line of a long group")
        return (shown + [more]).joined(separator: "\n")
    }

    /// Titles over 80 characters end at a word boundary with `…`.
    static func truncated(_ title: String) -> String {
        guard title.count > titleLimit else { return title }
        let cut = title.prefix(titleLimit - 1)
        let boundary = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return boundary.trimmingCharacters(in: .whitespaces) + "…"
    }

    /// `2h`, from `docs/02-activity-detection.md` §3.4's short form.
    static func ago(_ elapsed: TimeInterval) -> String {
        let seconds = max(0, elapsed)
        switch seconds {
        case ..<3600: return "\(max(1, Int(seconds / 60)))m"
        case ..<86400: return "\(Int(seconds / 3600))h"
        default: return "\(Int(seconds / 86400))d"
        }
    }
}
