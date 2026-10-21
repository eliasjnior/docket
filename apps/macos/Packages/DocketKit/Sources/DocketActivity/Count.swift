import DocketCore
import Foundation

/// The "needs you" number in the menu bar (`docs/02-activity-detection.md` §4).
public enum Count {
    public static let blockingStatuses: Set<Status> = [.conflict, .checksFailing, .changesRequested, .readyToMerge]

    public static func needsYou(_ item: WatchedPullRequest, settings: Config.Count = Config.Count()) -> Bool {
        guard !item.isIgnored else { return false }
        switch item.role {
        case .reviewRequested:
            return settings.includeReviewRequests
        case .authored:
            return settings.includeBlockedAuthored && !item.pullRequest.isDraft
                && blockingStatuses.contains(item.status)
        case .involved:
            return false
        }
    }

    public static func count(_ items: [WatchedPullRequest], settings: Config.Count = Config.Count()) -> Int {
        items.filter { needsYou($0, settings: settings) }.count
    }

    /// The menu bar text: none at 0, `99+` from 100.
    public static func label(_ count: Int) -> String? {
        switch count {
        case ..<1: nil
        case 1...99: "\(count)"
        default: "99+"
        }
    }
}
