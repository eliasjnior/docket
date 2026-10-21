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
    /// When the previous poll ran; the request that caused an entry notifies only if it is newer.
    public var previousPollAt: Date?

    public init(
        pullRequest: PullRequest, role: Role, detail: PullRequestDetail, cursor: Cursor, entering: Bool,
        isBaseline: Bool, previousPollAt: Date? = nil
    ) {
        self.pullRequest = pullRequest
        self.role = role
        self.detail = detail
        self.cursor = cursor
        self.entering = entering
        self.isBaseline = isBaseline
        self.previousPollAt = previousPollAt
    }
}

/// An event plus what folding and filtering need to know about the item behind it.
public struct RawEvent: Hashable, Sendable {
    public var event: Event
    public var author: Actor?
    /// For a review: the review. For a thread comment: the review it belongs to.
    public var reviewID: String?
    public var bodyIsEmpty: Bool

    public init(event: Event, author: Actor?, reviewID: String? = nil, bodyIsEmpty: Bool = false) {
        self.event = event
        self.author = author
        self.reviewID = reviewID
        self.bodyIsEmpty = bodyIsEmpty
    }
}

/// New items against a cursor, as events (`docs/02-activity-detection.md` §5.1–§5.3).
public enum Diff {
    public static func events(for subject: DiffSubject, viewer: ViewerContext) -> [RawEvent] {
        guard !subject.isBaseline else { return [] }
        let pullRequest = subject.pullRequest
        let detail = subject.detail
        let seen = Set(subject.cursor.seen)
        func isNew(_ id: String, _ at: Date?) -> Bool {
            guard let at, !seen.contains(id) else { return false }
            return at > subject.cursor.enteredAt
        }
        func event(_ kind: EventKind, _ id: String, _ url: URL, _ actor: Actor?, _ at: Date) -> Event {
            Event(
                kind: kind, itemID: id, pullRequestID: pullRequest.id, repository: pullRequest.repository,
                number: pullRequest.number, title: pullRequest.title, url: url, actor: actor?.login, at: at)
        }
        var raw: [RawEvent] = []

        if subject.role == .reviewRequested, let request = newRequest(subject, viewer: viewer, isNew: isNew) {
            var requested = event(.reviewRequested, request.id, pullRequest.url, request.actor, request.createdAt)
            if case .team = request.reviewer { requested.team = request.reviewer }
            raw.append(RawEvent(event: requested, author: request.actor))
        }
        if subject.role == .authored {
            for review in detail.reviews where isNew(review.id, review.submittedAt) {
                guard [.approved, .changesRequested, .commented].contains(review.state), let at = review.submittedAt
                else { continue }
                var submitted = event(.reviewSubmitted, review.id, pullRequest.url, review.author, at)
                submitted.decision = review.state
                raw.append(
                    RawEvent(
                        event: submitted, author: review.author, reviewID: review.id, bodyIsEmpty: review.bodyIsEmpty))
            }
            for comment in detail.comments where isNew(comment.id, comment.createdAt) {
                raw.append(
                    RawEvent(
                        event: event(.commentAdded, comment.id, comment.url, comment.author, comment.createdAt),
                        author: comment.author))
            }
        }
        raw.append(contentsOf: replies(in: detail, isNew: isNew, viewer: viewer, event: event))
        return raw
    }

    /// New review-thread comments in a thread where an earlier comment is yours (§5.3 `threadReply`).
    private static func replies(
        in detail: PullRequestDetail, isNew: (String, Date?) -> Bool, viewer: ViewerContext,
        event: (EventKind, String, URL, Actor?, Date) -> Event
    ) -> [RawEvent] {
        var raw: [RawEvent] = []
        for thread in detail.threads {
            let comments = thread.comments.sorted { $0.createdAt < $1.createdAt }
            for (index, comment) in comments.enumerated() where isNew(comment.id, comment.createdAt) {
                guard comments[..<index].contains(where: { viewer.isYou($0.author?.login) }) else { continue }
                raw.append(
                    RawEvent(
                        event: event(.threadReply, comment.id, comment.url, comment.author, comment.createdAt),
                        author: comment.author, reviewID: comment.reviewID))
            }
        }
        return raw
    }

    /// The latest new request addressed to you; on entry, only if it is newer than the previous poll.
    private static func newRequest(
        _ subject: DiffSubject, viewer: ViewerContext, isNew: (String, Date?) -> Bool
    ) -> ReviewRequestEvent? {
        let seen = Set(subject.cursor.seen)
        let mine = subject.detail.requestEvents.filter { event in
            switch viewer.isAddressedToYou(event.reviewer) {
            case .some(let addressed): return addressed
            case .none: return event.reviewer.map(subject.pullRequest.reviewRequests.contains) ?? false
            }
        }
        guard let latest = mine.max(by: { $0.createdAt < $1.createdAt }) else { return nil }
        if subject.entering {
            guard !seen.contains(latest.id) else { return nil }
            guard let previous = subject.previousPollAt else { return nil }
            return latest.createdAt > previous ? latest : nil
        }
        return isNew(latest.id, latest.createdAt) ? latest : nil
    }
}
