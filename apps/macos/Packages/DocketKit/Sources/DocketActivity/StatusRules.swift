import DocketCore
import Foundation

/// The status of a pull request, first match wins (`docs/02-activity-detection.md` §3).
public enum StatusRules {
    /// `UNKNOWN` is replaced by the last known value, or `MERGEABLE` when there is none (§3.1).
    public static func effectiveMergeable(_ current: Mergeable, last: Mergeable?) -> Mergeable {
        current == .unknown ? (last ?? .mergeable) : current
    }

    public static func status(of pullRequest: PullRequest, lastMergeable: Mergeable?) -> Status {
        if effectiveMergeable(pullRequest.mergeable, last: lastMergeable) == .conflicting { return .conflict }
        switch pullRequest.checks {
        case .failure, .error: return .checksFailing
        default: break
        }
        if isChangesRequested(pullRequest) { return .changesRequested }
        switch pullRequest.checks {
        case .pending, .expected: return .checksRunning
        default: break
        }
        if isApproved(pullRequest) { return .readyToMerge }
        if !pullRequest.reviewRequests.isEmpty { return .waitingForReview }
        return .noReviewers
    }

    public static func isApproved(_ pullRequest: PullRequest) -> Bool {
        switch pullRequest.reviewDecision {
        case .approved: true
        case nil:
            pullRequest.latestReviews.contains { $0.state == .approved }
                && !pullRequest.latestReviews.contains { $0.state == .changesRequested }
        default: false
        }
    }

    public static func isChangesRequested(_ pullRequest: PullRequest) -> Bool {
        switch pullRequest.reviewDecision {
        case .changesRequested: true
        case nil: pullRequest.latestReviews.contains { $0.state == .changesRequested }
        default: false
        }
    }
}
