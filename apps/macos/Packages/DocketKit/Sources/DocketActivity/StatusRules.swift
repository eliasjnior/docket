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
        case .pending, .expected:
            return waitingChecks(pullRequest).isEmpty ? .checksRunning : .checksWaiting
        default: break
        }
        if isApproved(pullRequest) { return .readyToMerge }
        if !pullRequest.reviewRequests.isEmpty { return .waitingForReview }
        return .noReviewers
    }

    /// The checks a person has to start or approve: none while any check run is still going (§3.2).
    public static func waitingChecks(_ pullRequest: PullRequest) -> [WaitingCheck] {
        guard let pending = pullRequest.pendingChecks, pending.running == 0 else { return [] }
        return pending.waiting.filter { asksAPerson($0, on: pullRequest) }
    }

    /// An approval always waits for a person. A pending commit status does when its link leads to the pull
    /// request's own page, as a gate that wants an `/e2e` comment does; a link elsewhere, or none, is an
    /// external CI still running, however long it takes.
    public static func asksAPerson(_ check: WaitingCheck, on pullRequest: PullRequest) -> Bool {
        if check.isApproval { return true }
        guard let url = check.url, url.host == pullRequest.url.host else { return false }
        return url.path == pullRequest.url.path || url.path.hasPrefix(pullRequest.url.path + "/")
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
