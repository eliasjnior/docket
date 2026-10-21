import DocketCore
import Foundation

/// Whether a poll can run, and if not, which screen or banner says why (`docs/05-design.md` §7).
public enum AccountState: Hashable, Sendable {
    /// The first poll of a launch has not finished.
    case loading
    case ready
    case ghNotFound
    case signedOut
    case missingScopes([String])

    /// A full screen replaces the list (`docs/05-design.md` §7.1).
    public var blocksPolling: Bool {
        switch self {
        case .ghNotFound, .signedOut, .missingScopes: true
        case .loading, .ready: false
        }
    }
}

/// Why the last poll did not update the list, for the banners of `docs/05-design.md` §7.2.
public enum PollProblem: Hashable, Sendable {
    case offline
    case rateLimited(until: Date)
    case failed(at: Date)
}

/// An organization whose results SAML left out (FR-13).
public struct SAMLOrganization: Hashable, Sendable, Identifiable {
    public var login: String
    public var url: URL

    public init(login: String, url: URL) {
        self.login = login
        self.url = url
    }

    public var id: String { login }
}

/// What the poller tells the interface after each poll, as one immutable value (`docs/03-architecture.md` §4).
public struct WatchSnapshot: Sendable {
    public var cache: SnapshotCache?
    public var state: PersistedState
    public var account: AccountState
    public var problem: PollProblem?
    public var isPolling: Bool
    public var samlOrganizations: [SAMLOrganization]

    public init(
        cache: SnapshotCache? = nil, state: PersistedState = PersistedState(), account: AccountState = .loading,
        problem: PollProblem? = nil, isPolling: Bool = false, samlOrganizations: [SAMLOrganization] = []
    ) {
        self.cache = cache
        self.state = state
        self.account = account
        self.problem = problem
        self.isPolling = isPolling
        self.samlOrganizations = samlOrganizations
    }
}
