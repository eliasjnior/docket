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
    /// Who merged it, once merged (FR-62).
    public var mergedBy: String?
    public var labels: [Label]
    public var headRefName: String?
    /// Issue links found in the body; the body itself is never kept (`docs/04-data.md` §5).
    public var issueLinks: [URL]
    public var headCommit: CommitStamp?
    public var lastForcePush: ActivityStamp?

    public init(
        id: String, number: Int, title: String, url: URL, state: PullRequestState = .open, isDraft: Bool = false,
        createdAt: Date, updatedAt: Date, author: Actor?, repository: String, isArchived: Bool = false,
        mergeable: Mergeable = .mergeable, reviewDecision: ReviewDecision? = nil, checks: CheckState? = nil,
        headOID: String? = nil, reviewRequests: [Reviewer] = [], latestReviews: [LatestReview] = [],
        mergedBy: String? = nil, labels: [Label] = [], headRefName: String? = nil, issueLinks: [URL] = [],
        headCommit: CommitStamp? = nil, lastForcePush: ActivityStamp? = nil
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
        self.mergedBy = mergedBy
        self.labels = labels
        self.headRefName = headRefName
        self.issueLinks = issueLinks
        self.headCommit = headCommit
        self.lastForcePush = lastForcePush
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        number = try c.decode(Int.self, forKey: .number)
        title = try c.decode(String.self, forKey: .title)
        url = try c.decode(URL.self, forKey: .url)
        state = try c.decode(PullRequestState.self, forKey: .state)
        isDraft = try c.decode(Bool.self, forKey: .isDraft)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        author = c.value(.author, default: nil)
        repository = try c.decode(String.self, forKey: .repository)
        isArchived = c.value(.isArchived, default: false)
        mergeable = c.value(.mergeable, default: .unknown)
        reviewDecision = c.value(.reviewDecision, default: nil)
        checks = c.value(.checks, default: nil)
        headOID = c.value(.headOID, default: nil)
        reviewRequests = c.value(.reviewRequests, default: [])
        latestReviews = c.value(.latestReviews, default: [])
        mergedBy = c.value(.mergedBy, default: nil)
        labels = c.value(.labels, default: [])
        headRefName = c.value(.headRefName, default: nil)
        issueLinks = c.value(.issueLinks, default: [])
        headCommit = c.value(.headCommit, default: nil)
        lastForcePush = c.value(.lastForcePush, default: nil)
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
