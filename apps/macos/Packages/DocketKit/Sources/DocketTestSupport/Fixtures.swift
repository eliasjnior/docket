import DocketCore
import Foundation

/// Synthetic data for tests: `acme/api`, `ana`, `bruno`, `carla`, `dave`, and `you` (CLAUDE.md, non-negotiable 8).
public enum Fixtures {
    public static let you = "you"
    /// 2026-10-21T12:00:00Z, the `now` every builder is relative to.
    public static let now = Date(timeIntervalSince1970: 1_792_584_000)

    public static func url(_ path: String) -> URL {
        URL(string: "https://github.com/\(path)") ?? URL(fileURLWithPath: "/")
    }

    public static func minutes(_ value: Double) -> TimeInterval { value * 60 }
    public static func hours(_ value: Double) -> TimeInterval { value * 3600 }
    public static func days(_ value: Double) -> TimeInterval { value * 86400 }

    public static func pullRequest(
        _ id: String = "PR_1", number: Int = 482, repository: String = "acme/api", author: String = "ana",
        title: String = "Fix login redirect loop", state: PullRequestState = .open, isDraft: Bool = false,
        createdAt: Date = now.addingTimeInterval(-days(2)), updatedAt: Date = now.addingTimeInterval(-hours(1)),
        isArchived: Bool = false, mergeable: Mergeable = .mergeable, decision: ReviewDecision? = nil,
        checks: CheckState? = nil, head: String? = "head1", requests: [Reviewer] = [],
        latestReviews: [LatestReview] = [], authorIsBot: Bool = false
    ) -> PullRequest {
        PullRequest(
            id: id, number: number, title: title, url: url("\(repository)/pull/\(number)"), state: state,
            isDraft: isDraft, createdAt: createdAt, updatedAt: updatedAt,
            author: Actor(login: author, isBot: authorIsBot), repository: repository, isArchived: isArchived,
            mergeable: mergeable, reviewDecision: decision, checks: checks, headOID: head,
            reviewRequests: requests, latestReviews: latestReviews
        )
    }

    public static func review(
        _ id: String, by login: String, _ state: ReviewState = .approved, at: Date, bodyIsEmpty: Bool = false,
        isBot: Bool = false
    ) -> Review {
        Review(
            id: id, state: state, bodyIsEmpty: bodyIsEmpty, submittedAt: at, author: Actor(login: login, isBot: isBot))
    }

    public static func comment(_ id: String, by login: String, at: Date, isBot: Bool = false) -> Comment {
        Comment(
            id: id, url: url("acme/api/pull/482#issuecomment-\(id)"), createdAt: at,
            author: Actor(login: login, isBot: isBot))
    }

    public static func threadComment(_ id: String, by login: String, at: Date, review: String? = nil) -> ThreadComment {
        ThreadComment(
            id: id, url: url("acme/api/pull/482#discussion_r\(id)"), createdAt: at, author: Actor(login: login),
            reviewID: review)
    }

    public static func request(
        _ id: String, to reviewer: Reviewer = .user(login: you), by login: String = "ana", at: Date
    ) -> ReviewRequestEvent {
        ReviewRequestEvent(id: id, createdAt: at, actor: Actor(login: login), reviewer: reviewer)
    }
}
