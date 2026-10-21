import Foundation

/// The summary of a pull request, as read by ID every poll (`docs/02-activity-detection.md` §6.1).
public struct PullRequest: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var number: Int
    public var title: String
    public var url: URL
    public var state: PullRequestState
    public var isDraft: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var author: Actor?
    /// `owner/name`.
    public var repository: String
    public var isArchived: Bool
    public var mergeable: Mergeable
    public var reviewDecision: ReviewDecision?
    public var checks: CheckState?
    public var headOID: String?
    public var reviewRequests: [Reviewer]
    public var latestReviews: [LatestReview]

    public init(
        id: String, number: Int, title: String, url: URL, state: PullRequestState = .open, isDraft: Bool = false,
        createdAt: Date, updatedAt: Date, author: Actor?, repository: String, isArchived: Bool = false,
        mergeable: Mergeable = .mergeable, reviewDecision: ReviewDecision? = nil, checks: CheckState? = nil,
        headOID: String? = nil, reviewRequests: [Reviewer] = [], latestReviews: [LatestReview] = []
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.url = url
        self.state = state
        self.isDraft = isDraft
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.author = author
        self.repository = repository
        self.isArchived = isArchived
        self.mergeable = mergeable
        self.reviewDecision = reviewDecision
        self.checks = checks
        self.headOID = headOID
        self.reviewRequests = reviewRequests
        self.latestReviews = latestReviews
    }

    /// `owner/name#number`, the form that pastes as a GitHub reference.
    public var ref: String { "\(repository)#\(number)" }

    public var owner: String { String(repository.split(separator: "/").first ?? "") }
}

/// One reviewer's latest `APPROVED` or `CHANGES_REQUESTED` review.
public struct LatestReview: Codable, Hashable, Sendable {
    public var login: String
    public var state: ReviewState

    public init(login: String, state: ReviewState) {
        self.login = login
        self.state = state
    }
}
