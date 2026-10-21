import DocketCore
import Foundation

/// The latest review request to you, for the waited time and the row's team (`docs/02-activity-detection.md` §3.4).
public enum Requests {
    public static func latest(
        on pullRequest: PullRequest, detail: PullRequestDetail?, viewer: ViewerContext
    ) -> RequestInfo? {
        let events = (detail?.requestEvents ?? []).filter { event in
            switch viewer.isAddressedToYou(event.reviewer) {
            case .some(let mine): return mine
            case .none: return event.reviewer.map(pullRequest.reviewRequests.contains) ?? false
            }
        }
        if let event = events.max(by: { $0.createdAt < $1.createdAt }) {
            let team: Reviewer? = if case .team = event.reviewer { event.reviewer } else { nil }
            return RequestInfo(
                requestedAt: event.createdAt, requestedBy: event.actor?.login, team: team,
                throughUnknownTeam: team != nil && viewer.teams == nil)
        }
        let direct = pullRequest.reviewRequests.contains { viewer.isAddressedToYou($0) == true }
        let team = direct ? nil : pullRequest.reviewRequests.first { viewer.isAddressedToYou($0) != false }
        return RequestInfo(
            requestedAt: pullRequest.createdAt, requestedBy: nil, team: team,
            throughUnknownTeam: team != nil && viewer.teams == nil)
    }
}
