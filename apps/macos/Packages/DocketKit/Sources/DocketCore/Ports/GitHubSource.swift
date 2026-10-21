import Foundation

/// Read-only access to GitHub (`docs/03-architecture.md` §7). Docket never writes to GitHub.
public protocol GitHubSource: Sendable {
    func viewer() async throws -> GitHubResponse<Viewer>
    func discover(login: String, since: Date) async throws -> GitHubResponse<Discovery>
    func summaries(ids: [String]) async throws -> GitHubResponse<SummaryBatch>
    func details(ids: [String]) async throws -> GitHubResponse<[PullRequestDetail]>
    func teams(organization: String, login: String) async throws -> GitHubResponse<[String]>
    func repositoryExists(_ nameWithOwner: String) async throws -> Bool
}

public struct Viewer: Codable, Hashable, Sendable {
    public var login: String

    public init(login: String) {
        self.login = login
    }
}

/// The pull requests one `nodes(ids:)` query returned, and the IDs it could not read.
public struct SummaryBatch: Hashable, Sendable {
    public var pullRequests: [PullRequest]
    /// `NOT_FOUND`: access was lost or the pull request was deleted.
    public var notFound: [String]
    /// Other per-node errors, SAML included: these keep their previous snapshot for this poll.
    public var failed: [String]

    public init(pullRequests: [PullRequest] = [], notFound: [String] = [], failed: [String] = []) {
        self.pullRequests = pullRequests
        self.notFound = notFound
        self.failed = failed
    }
}

/// A value plus what the response's headers and `rateLimit` said.
public struct GitHubResponse<Value: Sendable>: Sendable {
    public var value: Value
    public var meta: ResponseMeta

    public init(value: Value, meta: ResponseMeta = ResponseMeta()) {
        self.value = value
        self.meta = meta
    }
}

public struct ResponseMeta: Hashable, Sendable {
    public var rateLimit: RateLimit?
    /// The `Date` header.
    public var serverDate: Date?
    /// `X-OAuth-Scopes`, when present.
    public var scopes: [String]?
    /// Organizations whose results `X-GitHub-SSO: partial-results` left out, by login.
    public var samlOrganizations: [String]
    /// The authorization URL of `X-GitHub-SSO: required; url=…`.
    public var samlURL: URL?

    public init(
        rateLimit: RateLimit? = nil, serverDate: Date? = nil, scopes: [String]? = nil,
        samlOrganizations: [String] = [], samlURL: URL? = nil
    ) {
        self.rateLimit = rateLimit
        self.serverDate = serverDate
        self.scopes = scopes
        self.samlOrganizations = samlOrganizations
        self.samlURL = samlURL
    }
}

public struct RateLimit: Codable, Hashable, Sendable {
    public var cost: Int
    public var remaining: Int
    public var limit: Int
    public var resetAt: Date?

    public init(cost: Int, remaining: Int, limit: Int, resetAt: Date?) {
        self.cost = cost
        self.remaining = remaining
        self.limit = limit
        self.resetAt = resetAt
    }
}

public enum GitHubError: Error, Hashable, Sendable {
    /// `401` after the token was re-read once (FR-14).
    case unauthorized
    case missingScopes([String])
    /// `403`/`429` with `Retry-After`, in seconds.
    case secondaryRateLimit(retryAfter: TimeInterval)
    case rateLimited(resetAt: Date?)
    case network
    case server(status: Int)
    case invalidResponse(String)
}
