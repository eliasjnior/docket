import Foundation

/// One notification Docket decided to send, before it is worded (`docs/02-activity-detection.md` §7).
public struct PlannedNotification: Hashable, Sendable {
    public enum Content: Hashable, Sendable {
        /// Events of one kind in one repository, oldest first.
        case events(EventKind, [Event])
        case reminders([Reminder])
        /// `N more updates in M repositories`.
        case overflow(updates: Int, repositories: Int)
        /// `While you were in Focus`, every held kind of one repository.
        case digest([HeldEvent])
    }

    public var repository: String?
    public var content: Content

    public init(repository: String?, content: Content) {
        self.repository = repository
        self.content = content
    }

    /// Every event or reminder ID this notification carries, for the `delivered` ledger.
    public var deliveredIDs: [String] {
        switch content {
        case .events(_, let events): events.map(\.id)
        case .reminders(let reminders): reminders.map(\.id)
        case .overflow: []
        case .digest(let held): held.map(\.eventID)
        }
    }
}

/// A review request still pending one interval after the request or the last reminder.
public struct Reminder: Hashable, Sendable, Identifiable {
    public var pullRequestID: String
    public var repository: String
    public var number: Int
    public var title: String
    public var url: URL
    public var requestedAt: Date
    public var requestedBy: String?
    public var at: Date

    public init(
        pullRequestID: String, repository: String, number: Int, title: String, url: URL, requestedAt: Date,
        requestedBy: String?, at: Date
    ) {
        self.pullRequestID = pullRequestID
        self.repository = repository
        self.number = number
        self.title = title
        self.url = url
        self.requestedAt = requestedAt
        self.requestedBy = requestedBy
        self.at = at
    }

    public var id: String { "reviewReminder:\(pullRequestID)" }
}
