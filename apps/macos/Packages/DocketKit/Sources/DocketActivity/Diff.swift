import DocketCore
import Foundation

/// One pull request's items against its cursor.
public struct DiffSubject: Hashable, Sendable {
    public var pullRequest: PullRequest
    public var role: Role
    public var detail: PullRequestDetail
    public var cursor: Cursor
    /// It gained a role this poll (`docs/02-activity-detection.md` §2.4).
    public var entering: Bool
    /// The first poll of a fresh install (D-19).
    public var isBaseline: Bool

    public init(
        pullRequest: PullRequest, role: Role, detail: PullRequestDetail, cursor: Cursor, entering: Bool,
        isBaseline: Bool
    ) {
        self.pullRequest = pullRequest
        self.role = role
        self.detail = detail
        self.cursor = cursor
        self.entering = entering
        self.isBaseline = isBaseline
    }
}

/// New items against a cursor, as events (`docs/02-activity-detection.md` §5.1–§5.3).
public enum Diff {
    public static func events(for subject: DiffSubject, viewer: ViewerContext) -> [Event] {
        []
    }
}
