import DocketCore
import Foundation

/// One reviewer on an authored pull request's row (FR-35).
public struct ReviewerEntry: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        case pending
        case approved
        case changesRequested
        case commented
    }

    /// `@ana` or `@acme/backend`.
    public var handle: String
    public var state: State
    /// Requested again after a decision.
    public var reRequested: Bool

    public init(handle: String, state: State, reRequested: Bool = false) {
        self.handle = handle
        self.state = state
        self.reRequested = reRequested
    }
}

/// Pending requests first, then decisions, then reviewers who only commented (`docs/02-activity-detection.md` §3.3).
public enum Reviewers {
    public static func entries(for pullRequest: PullRequest, commenters: [String]) -> [ReviewerEntry] {
        let decided = Dictionary(
            pullRequest.latestReviews.map { ($0.login.lowercased(), $0.state) }, uniquingKeysWith: { _, last in last })
        var entries: [ReviewerEntry] = []
        var listed = Set<String>()
        for reviewer in pullRequest.reviewRequests {
            if case .user(let login) = reviewer, decided[login.lowercased()] != nil { continue }
            entries.append(ReviewerEntry(handle: reviewer.handle, state: .pending))
            listed.insert(reviewer.handle.lowercased())
        }
        let requestedUsers = Set(
            pullRequest.reviewRequests.compactMap { reviewer -> String? in
                if case .user(let login) = reviewer { return login.lowercased() }
                return nil
            })
        for review in pullRequest.latestReviews where !listed.contains("@\(review.login.lowercased())") {
            let state: ReviewerEntry.State = review.state == .approved ? .approved : .changesRequested
            entries.append(
                ReviewerEntry(
                    handle: "@\(review.login)", state: state,
                    reRequested: requestedUsers.contains(review.login.lowercased())))
            listed.insert("@\(review.login.lowercased())")
        }
        for login in commenters where !listed.contains("@\(login.lowercased())") {
            entries.append(ReviewerEntry(handle: "@\(login)", state: .commented))
            listed.insert("@\(login.lowercased())")
        }
        return entries
    }

    /// Reviewers whose only submitted reviews are `COMMENTED`, excluding the author and you.
    public static func commenters(in detail: PullRequestDetail, pullRequest: PullRequest, viewer: ViewerContext)
        -> [String]
    {
        var states: [String: Set<ReviewState>] = [:]
        var order: [String] = []
        for review in detail.reviews {
            guard let login = review.author?.login, !viewer.isYou(login),
                login.lowercased() != pullRequest.author?.login.lowercased()
            else { continue }
            if states[login] == nil { order.append(login) }
            states[login, default: []].insert(review.state)
        }
        return order.filter { states[$0] == [.commented] }
    }
}
