import Foundation

/// The items of a pull request, read only when it changed (`docs/02-activity-detection.md` §6.1).
public struct PullRequestDetail: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var reviews: [Review]
    public var comments: [Comment]
    public var threads: [ReviewThread]
    public var requestEvents: [ReviewRequestEvent]
    /// Who closed it, from the latest `ClosedEvent` (FR-62).
    public var closedBy: String?

    public init(
        id: String, reviews: [Review] = [], comments: [Comment] = [], threads: [ReviewThread] = [],
        requestEvents: [ReviewRequestEvent] = [], closedBy: String? = nil
    ) {
        self.id = id
        self.reviews = reviews
        self.comments = comments
        self.threads = threads
        self.requestEvents = requestEvents
        self.closedBy = closedBy
    }

    /// Every item ID a cursor tracks.
    public var itemIDs: [String] {
        reviews.map(\.id) + comments.map(\.id) + threads.flatMap { $0.comments.map(\.id) } + requestEvents.map(\.id)
    }
}

public struct Review: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var state: ReviewState
    /// The body itself is never kept (`docs/04-data.md` §5).
    public var bodyIsEmpty: Bool
    public var submittedAt: Date?
    public var author: Actor?
    /// Logins the text mentions; the text itself is never kept.
    public var mentions: [String]

    public init(
        id: String, state: ReviewState, bodyIsEmpty: Bool = true, submittedAt: Date?, author: Actor?,
        mentions: [String] = []
    ) {
        self.id = id
        self.state = state
        self.bodyIsEmpty = bodyIsEmpty
        self.submittedAt = submittedAt
        self.author = author
        self.mentions = mentions
    }
}

public struct Comment: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var url: URL
    public var createdAt: Date
    public var author: Actor?
    public var mentions: [String]

    public init(id: String, url: URL, createdAt: Date, author: Actor?, mentions: [String] = []) {
        self.id = id
        self.url = url
        self.createdAt = createdAt
        self.author = author
        self.mentions = mentions
    }
}

public struct ReviewThread: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var comments: [ThreadComment]

    public init(id: String, comments: [ThreadComment]) {
        self.id = id
        self.comments = comments
    }
}

public struct ThreadComment: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var url: URL
    public var createdAt: Date
    public var author: Actor?
    public var reviewID: String?
    public var mentions: [String]

    public init(
        id: String, url: URL, createdAt: Date, author: Actor?, reviewID: String? = nil, mentions: [String] = []
    ) {
        self.id = id
        self.url = url
        self.createdAt = createdAt
        self.author = author
        self.reviewID = reviewID
        self.mentions = mentions
    }
}

public struct ReviewRequestEvent: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var createdAt: Date
    public var actor: Actor?
    public var reviewer: Reviewer?

    public init(id: String, createdAt: Date, actor: Actor?, reviewer: Reviewer?) {
        self.id = id
        self.createdAt = createdAt
        self.actor = actor
        self.reviewer = reviewer
    }
}

/// The logins a text mentions: `@login` as a whole word, never a team (`@org/team`).
public enum Mentions {
    public static func logins(in text: String?) -> [String] {
        guard let text, text.contains("@") else { return [] }
        let pattern = #"(?<![A-Za-z0-9_@/.-])@([A-Za-z0-9](?:[A-Za-z0-9-]{0,38}))(?![A-Za-z0-9_/-])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        return regex.matches(in: text, range: range).compactMap { match in
            guard let login = Range(match.range(at: 1), in: text).map({ String(text[$0]) }) else { return nil }
            return seen.insert(login.lowercased()).inserted ? login : nil
        }
    }
}
