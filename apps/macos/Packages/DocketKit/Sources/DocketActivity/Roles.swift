import DocketCore
import Foundation

/// Which searches found a pull request this poll.
public struct DiscoveryHits: Hashable, Sendable {
    public var requested: Bool
    /// Found by `commented` or `reviewed`.
    public var involved: Bool

    public init(requested: Bool = false, involved: Bool = false) {
        self.requested = requested
        self.involved = involved
    }

    public init(_ discovery: Discovery, id: String) {
        requested = discovery.requested.contains(id)
        involved = discovery.commented.contains(id) || discovery.reviewed.contains(id)
    }
}

/// What one poll knows about a pull request when assigning its role.
public struct Candidate: Hashable, Sendable {
    public var pullRequest: PullRequest
    /// `nil` when the details were not read this poll because nothing changed.
    public var detail: PullRequestDetail?
    public var hits: DiscoveryHits
    public var previous: Cursor?

    public init(
        pullRequest: PullRequest, detail: PullRequestDetail?, hits: DiscoveryHits = DiscoveryHits(),
        previous: Cursor? = nil
    ) {
        self.pullRequest = pullRequest
        self.detail = detail
        self.hits = hits
        self.previous = previous
    }
}

/// One role per pull request, by precedence (`docs/02-activity-detection.md` §2.2, D-08).
public enum Roles {
    public static let involvedWindow: TimeInterval = 30 * 86400

    public static func role(of candidate: Candidate, viewer: ViewerContext, now: Date) -> Role? {
        let pullRequest = candidate.pullRequest
        let hits = candidate.hits
        let previous = candidate.previous
        guard pullRequest.state == .open, !pullRequest.isArchived else { return nil }
        if viewer.isYou(pullRequest.author?.login) { return .authored }
        switch requestStatus(of: candidate, viewer: viewer) {
        case .pending: return .reviewRequested
        case .answered: return .involved
        case .none: break
        }
        if hits.involved { return .involved }
        if previous?.role == .involved, now.timeIntervalSince(pullRequest.updatedAt) <= involvedWindow {
            return .involved
        }
        return nil
    }

    enum RequestStatus {
        case pending
        /// A team request you already reviewed after: the pull request drops to `involved`.
        case answered
        case none
    }

    static func requestStatus(of candidate: Candidate, viewer: ViewerContext) -> RequestStatus {
        var answered = false
        for reviewer in candidate.pullRequest.reviewRequests {
            switch reviewer {
            case .user:
                if viewer.isAddressedToYou(reviewer) == true { return .pending }
            case .team:
                switch viewer.isAddressedToYou(reviewer) {
                case .some(true):
                    if reviewedAfterLatestRequest(to: reviewer, in: candidate, viewer: viewer) {
                        answered = true
                    } else {
                        return .pending
                    }
                case .some(false): continue
                case .none:
                    if candidate.hits.requested { return .pending }
                }
            }
        }
        return answered ? .answered : .none
    }

    private static func reviewedAfterLatestRequest(to team: Reviewer, in candidate: Candidate, viewer: ViewerContext)
        -> Bool
    {
        guard let detail = candidate.detail else { return candidate.previous?.role == .involved }
        let requestedAt = detail.requestEvents.filter { $0.reviewer == team }.map(\.createdAt).max()
        let reviewedAt = detail.reviews
            .filter { viewer.isYou($0.author?.login) && $0.state != .pending }
            .compactMap(\.submittedAt).max()
        guard let reviewedAt else { return false }
        guard let requestedAt else { return true }
        return reviewedAt > requestedAt
    }
}
