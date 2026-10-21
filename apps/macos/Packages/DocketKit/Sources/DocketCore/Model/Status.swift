import Foundation

/// One status per pull request, in the precedence order of `docs/02-activity-detection.md` §3.2.
public enum Status: String, Codable, Hashable, Sendable, CaseIterable, Comparable {
    case conflict
    case checksFailing
    case changesRequested
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
        case .checksRunning: 3
        case .readyToMerge: 4
        case .waitingForReview: 5
        case .noReviewers: 6
        }
    }

    public static func < (lhs: Status, rhs: Status) -> Bool { lhs.rank < rhs.rank }
}
