import Foundation

/// One status per pull request, in the precedence order of `docs/02-activity-detection.md` §3.2.
public enum Status: String, Codable, Hashable, Sendable, CaseIterable, Comparable {
    case conflict
    case checksFailing
    case changesRequested
    /// Pending, nothing running, and a check waits for a person (§3.2).
    case checksWaiting
    case checksRunning
    case readyToMerge
    case waitingForReview
    case noReviewers

    /// Position in the precedence order, `conflict` first.
    public var rank: Int {
        switch self {
        case .conflict: 0
        case .checksFailing: 1
        case .changesRequested: 2
        case .checksWaiting: 3
        case .checksRunning: 4
        case .readyToMerge: 5
        case .waitingForReview: 6
        case .noReviewers: 7
        }
    }

    public static func < (lhs: Status, rhs: Status) -> Bool { lhs.rank < rhs.rank }
}
