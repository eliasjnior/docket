import Foundation

/// The items of a pull request, read only when it changed (`docs/02-activity-detection.md` §6.1).
public struct PullRequestDetail: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var reviews: [Review]
    public var comments: [Comment]
    public var threads: [ReviewThread]
    public var requestEvents: [ReviewRequestEvent]

    public init(
        id: String, reviews: [Review] = [], comments: [Comment] = [], threads: [ReviewThread] = [],
        requestEvents: [ReviewRequestEvent] = []
    ) {
        self.id = id
        self.reviews = reviews
        self.comments = comments
        self.threads = threads
        self.requestEvents = requestEvents
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

    public init(id: String, state: ReviewState, bodyIsEmpty: Bool = true, submittedAt: Date?, author: Actor?) {
        self.id = id
        self.state = state
        self.bodyIsEmpty = bodyIsEmpty
        self.submittedAt = submittedAt
        self.author = author
    }
}

public struct Comment: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var url: URL
    public var createdAt: Date
    public var author: Actor?

    public init(id: String, url: URL, createdAt: Date, author: Actor?) {
        self.id = id
        self.url = url
        self.createdAt = createdAt
        self.author = author
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

    public init(id: String, url: URL, createdAt: Date, author: Actor?, reviewID: String? = nil) {
        self.id = id
        self.url = url
        self.createdAt = createdAt
        self.author = author
        self.reviewID = reviewID
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
