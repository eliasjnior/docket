import DocketCore
import Foundation

/// How big a pull request is, by the lines it changes (`docs/05-design.md` §6.1): a small one is reviewed
/// sooner, so a large one is worth noticing before you ask for a review.
public enum PullRequestSize: String, CaseIterable, Comparable, Sendable {
    case extraSmall
    case small
    case medium
    case large
    case extraLarge

    /// The upper bound of each size, in lines added plus deleted.
    static let limits: [(PullRequestSize, Int)] = [
        (.extraSmall, 10), (.small, 100), (.medium, 400), (.large, 1000),
    ]

    /// `nil` when the cache predates the line counts.
    public static func of(_ pullRequest: PullRequest) -> PullRequestSize? {
        guard let additions = pullRequest.additions, let deletions = pullRequest.deletions else { return nil }
        return of(lines: additions + deletions)
    }

    /// The size of any number of changed lines, such as a whole stack's.
    public static func of(lines: Int) -> PullRequestSize {
        limits.first { lines <= $0.1 }?.0 ?? .extraLarge
    }

    /// Large and extra large: past the size a reviewer reads in one sitting.
    public var isLarge: Bool { self >= .large }

    public static func < (lhs: PullRequestSize, rhs: PullRequestSize) -> Bool {
        allCases.firstIndex(of: lhs) ?? 0 < allCases.firstIndex(of: rhs) ?? 0
    }
}
