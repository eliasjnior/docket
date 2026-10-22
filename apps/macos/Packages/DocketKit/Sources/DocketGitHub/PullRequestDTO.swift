import DocketCore
import Foundation

/// The summary query's node. Every field is optional: a node that is not a pull request decodes as `{}`.
struct PullRequestDTO: Decodable {
    struct Repository: Decodable {
        var nameWithOwner: String
        var isArchived: Bool
    }

    struct Commit: Decodable {
        var commit: CommitDTO
    }

    struct RequestNode: Decodable {
        var requestedReviewer: RequestedReviewerDTO?
    }

    struct LabelNode: Decodable {
        var name: String
        var color: String
    }

    struct ForcePushNode: Decodable {
        var createdAt: Date?
        var actor: ActorDTO?
    }

    struct LatestReviewNode: Decodable {
        struct Login: Decodable { var login: String }
        var author: Login?
        var state: String
    }

    var id: String?
    var number: Int?
    var title: String?
    var url: URL?
    var state: String?
    var isDraft: Bool?
    var createdAt: Date?
    var updatedAt: Date?
    var author: ActorDTO?
    var repository: Repository?
    var mergeable: String?
    var reviewDecision: String?
    var commits: Connection<Commit>?
    var reviewRequests: Connection<RequestNode>?
    var latestOpinionatedReviews: Connection<LatestReviewNode>?
    var mergedBy: LatestReviewNode.Login?
    var body: String?
    var headRefName: String?
    var labels: Connection<LabelNode>?
    var timelineItems: Connection<ForcePushNode>?

    var value: PullRequest? {
        guard let id, let number, let title, let url, let createdAt, let updatedAt, let repository else { return nil }
        let head = commits?.values.last?.commit
        return PullRequest(
            id: id, number: number, title: title, url: url, state: PullRequestState(rawValue: state ?? "") ?? .open,
            isDraft: isDraft ?? false, createdAt: createdAt, updatedAt: updatedAt, author: author?.value,
            repository: repository.nameWithOwner, isArchived: repository.isArchived,
            mergeable: Mergeable(rawValue: mergeable ?? "") ?? .unknown,
            reviewDecision: reviewDecision.flatMap(ReviewDecision.init(rawValue:)),
            checks: head?.statusCheckRollup?.state.flatMap(CheckState.init(rawValue:)), headOID: head?.oid,
            reviewRequests: reviewRequests?.values.compactMap { $0.requestedReviewer?.value } ?? [],
            latestReviews: latestOpinionatedReviews?.values.compactMap { node in
                guard let login = node.author?.login, let state = ReviewState(rawValue: node.state) else { return nil }
                return LatestReview(login: login, state: state)
            } ?? [],
            mergedBy: mergedBy?.login,
            labels: labels?.values.map { Label(name: $0.name, color: $0.color) } ?? [],
            headRefName: headRefName, issueLinks: IssueLinks.urls(in: body),
            headCommit: head.flatMap { commit in
                commit.committedDate.map {
                    CommitStamp(
                        login: commit.author?.user?.login,
                        isBot: (commit.author?.name ?? "").hasSuffix("[bot]"), at: $0)
                }
            },
            lastForcePush: timelineItems?.values.last.flatMap { node in
                guard let at = node.createdAt, let actor = node.actor?.value else { return nil }
                return ActivityStamp(login: actor.login, isBot: actor.isBot, at: at)
            }
        )
    }
}

/// Links to issues in a pull request body, such as Jira's `…/browse/ABC-123`. The body itself is dropped.
enum IssueLinks {
    static func urls(in body: String?) -> [URL] {
        guard let body, !body.isEmpty else { return [] }
        let pattern = #"https?://[^\s)\]>"']+/browse/[A-Z][A-Z0-9]+-\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(body.startIndex..., in: body)
        var seen = Set<String>()
        return regex.matches(in: body, range: range).compactMap { match in
            guard let span = Range(match.range, in: body) else { return nil }
            let text = String(body[span])
            guard seen.insert(text).inserted else { return nil }
            return URL(string: text)
        }
    }
}

/// The detail query's node.
struct DetailDTO: Decodable {
    struct ReviewNode: Decodable {
        var id: String
        var state: String
        var body: String?
        var submittedAt: Date?
        var author: ActorDTO?
    }

    struct CommentNode: Decodable {
        var id: String
        var url: URL
        var body: String?
        var createdAt: Date
        var author: ActorDTO?
    }

    struct ThreadNode: Decodable {
        var id: String
        var comments: Connection<ThreadCommentDTO>?
    }

    struct RequestEventNode: Decodable {
        var typename: String?
        var id: String?
        var createdAt: Date?
        var actor: ActorDTO?
        var requestedReviewer: RequestedReviewerDTO?

        enum CodingKeys: String, CodingKey {
            case typename = "__typename"
            case id, createdAt, actor, requestedReviewer
        }
    }

    var id: String?
    var reviews: Connection<ReviewNode>?
    var comments: Connection<CommentNode>?
    var reviewThreads: Connection<ThreadNode>?
    var timelineItems: Connection<RequestEventNode>?

    var value: PullRequestDetail? {
        guard let id else { return nil }
        return PullRequestDetail(
            id: id,
            reviews: reviews?.values.map { node in
                Review(
                    id: node.id, state: ReviewState(rawValue: node.state) ?? .commented,
                    bodyIsEmpty: (node.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    submittedAt: node.submittedAt, author: node.author?.value, mentions: Mentions.logins(in: node.body))
            } ?? [],
            comments: comments?.values.map { node in
                Comment(
                    id: node.id, url: node.url, createdAt: node.createdAt, author: node.author?.value,
                    mentions: Mentions.logins(in: node.body))
            } ?? [],
            threads: reviewThreads?.values.map { thread in
                ReviewThread(
                    id: thread.id,
                    comments: thread.comments?.values.map { node in
                        ThreadComment(
                            id: node.id, url: node.url, createdAt: node.createdAt, author: node.author?.value,
                            reviewID: node.pullRequestReview?.id, mentions: Mentions.logins(in: node.body))
                    } ?? [])
            } ?? [],
            requestEvents: timelineItems?.values.compactMap { node in
                guard node.typename != "ClosedEvent", let id = node.id, let createdAt = node.createdAt else {
                    return nil
                }
                return ReviewRequestEvent(
                    id: id, createdAt: createdAt, actor: node.actor?.value, reviewer: node.requestedReviewer?.value)
            } ?? [],
            closedBy: timelineItems?.values.filter { $0.typename == "ClosedEvent" }
                .max { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }?.actor?.login
        )
    }
}

struct CommitDTO: Decodable {
    struct Rollup: Decodable { var state: String? }
    struct Author: Decodable {
        struct User: Decodable { var login: String }
        var name: String?
        var user: User?
    }

    var oid: String?
    var committedDate: Date?
    var author: Author?
    var statusCheckRollup: Rollup?
}

struct ThreadCommentDTO: Decodable {
    struct ReviewID: Decodable { var id: String }
    var id: String
    var url: URL
    var body: String?
    var createdAt: Date
    var author: ActorDTO?
    var pullRequestReview: ReviewID?
}
