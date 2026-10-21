import Foundation

public enum EventKind: String, Codable, Hashable, Sendable, CaseIterable {
    case reviewRequested
    case reviewSubmitted
    case commentAdded
    case threadReply
    case checksFailed
    case closedByOther
    case mention
}

/// Something that happened on GitHub and may be worth a notification (`docs/02-activity-detection.md` §5).
public struct Event: Codable, Hashable, Sendable, Identifiable {
    /// `<kind>:<item node ID>` (`docs/04-data.md` §2.2).
    public var id: String
    public var kind: EventKind
    public var pullRequestID: String
    public var repository: String
    public var number: Int
    public var title: String
    /// What a click opens: the comment for a comment or reply, the pull request otherwise.
    public var url: URL
    public var actor: String?
    public var decision: ReviewState?
    /// The team a review request reached you through.
    public var team: Reviewer?
    public var at: Date

    public init(
        kind: EventKind, itemID: String, pullRequestID: String, repository: String, number: Int, title: String,
        url: URL, actor: String?, decision: ReviewState? = nil, team: Reviewer? = nil, at: Date
    ) {
        id = "\(kind.rawValue):\(itemID)"
        self.kind = kind
        self.pullRequestID = pullRequestID
        self.repository = repository
        self.number = number
        self.title = title
        self.url = url
        self.actor = actor
        self.decision = decision
        self.team = team
        self.at = at
    }
}
