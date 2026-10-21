import Foundation

/// `cache/snapshot.json`: what GitHub said last, so the popover renders at once (`docs/04-data.md` §2.3).
public struct SnapshotCache: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var fetchedAt: Date
    public var viewerLogin: String
    public var pullRequests: [CachedPullRequest]
    public var knownRepositories: [KnownRepository]
    public var notShown: [String: Int]

    public init(
        fetchedAt: Date, viewerLogin: String, pullRequests: [CachedPullRequest] = [],
        knownRepositories: [KnownRepository] = [], notShown: [String: Int] = [:]
    ) {
        version = Self.currentVersion
        self.fetchedAt = fetchedAt
        self.viewerLogin = viewerLogin
        self.pullRequests = pullRequests
        self.knownRepositories = knownRepositories
        self.notShown = notShown
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.value(.version, default: Self.currentVersion)
        fetchedAt = try c.decode(Date.self, forKey: .fetchedAt)
        viewerLogin = try c.decode(String.self, forKey: .viewerLogin)
        pullRequests = c.value(.pullRequests, default: [])
        knownRepositories = c.value(.knownRepositories, default: [])
        notShown = c.value(.notShown, default: [:])
    }
}

/// A summary plus what the detail read said about the latest request, for display.
public struct CachedPullRequest: Codable, Hashable, Sendable, Identifiable {
    public var pullRequest: PullRequest
    public var role: Role
    public var request: RequestInfo?
    /// Reviewers whose only reviews are `COMMENTED` (`docs/02-activity-detection.md` §3.3).
    public var commenters: [String]

    public init(pullRequest: PullRequest, role: Role, request: RequestInfo? = nil, commenters: [String] = []) {
        self.pullRequest = pullRequest
        self.role = role
        self.request = request
        self.commenters = commenters
    }

    public var id: String { pullRequest.id }
}

/// The latest review request addressed to you or a team you belong to.
public struct RequestInfo: Codable, Hashable, Sendable {
    public var requestedAt: Date
    public var requestedBy: String?
    /// Set when the request reached you through a team; `unknownTeam` without `read:org`.
    public var team: Reviewer?
    public var throughUnknownTeam: Bool

    public init(requestedAt: Date, requestedBy: String?, team: Reviewer? = nil, throughUnknownTeam: Bool = false) {
        self.requestedAt = requestedAt
        self.requestedBy = requestedBy
        self.team = team
        self.throughUnknownTeam = throughUnknownTeam
    }
}

public struct KnownRepository: Codable, Hashable, Sendable {
    public var name: String
    public var lastSeenAt: Date

    public init(name: String, lastSeenAt: Date) {
        self.name = name
        self.lastSeenAt = lastSeenAt
    }
}
