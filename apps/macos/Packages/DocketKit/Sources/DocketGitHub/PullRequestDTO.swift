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
    var baseRefName: String?
    var labels: Connection<LabelNode>?
    var timelineItems: Connection<ForcePushNode>?
    var additions: Int?
    var deletions: Int?
    var changedFiles: Int?

    var value: PullRequest? {
        guard let id, let number, let title, let url, let createdAt, let updatedAt, let repository else { return nil }
        let head = commits?.values.last?.commit
        return PullRequest(
            id: id, number: number, title: title, url: url, state: PullRequestState(rawValue: state ?? "") ?? .open,
            isDraft: isDraft ?? false, createdAt: createdAt, updatedAt: updatedAt, author: author?.value,
            repository: repository.nameWithOwner, isArchived: repository.isArchived,
            mergeable: Mergeable(rawValue: mergeable ?? "") ?? .unknown,
            reviewDecision: reviewDecision.flatMap(ReviewDecision.init(rawValue:)),
            checks: head?.statusCheckRollup?.checks, headOID: head?.oid,
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
            },
            additions: additions, deletions: deletions, changedFiles: changedFiles, baseRefName: baseRefName,
            links: Links.extract(from: body).filter { $0.url.absoluteString != url.absoluteString }
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
                    mentions: Mentions.logins(in: node.body),
                    links: Links.extract(from: node.body, source: node.author?.value?.login))
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

/// One entry of a rollup's contexts: a check run or a commit status.
struct CheckContextDTO: Decodable {
    var typename: String?
    var name: String?
    var status: String?
    var detailsUrl: URL?
    var context: String?
    var state: String?
    var description: String?
    var targetUrl: URL?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case name, status, detailsUrl, context, state, description, targetUrl
    }
}

/// A pull request in the answer to `Queries.checks`.
struct ChecksDTO: Decodable {
    struct Commit: Decodable { var statusCheckRollup: CommitDTO.Rollup? }
    struct CommitNode: Decodable { var commit: Commit? }
    var id: String?
    var commits: Connection<CommitNode>?

    var pendingChecks: PendingChecks? { commits?.values.last?.commit?.statusCheckRollup?.pendingChecks }
}

struct CommitDTO: Decodable {
    struct Rollup: Decodable {
        static let runningStatuses: Set<String> = ["QUEUED", "IN_PROGRESS", "PENDING", "REQUESTED"]

        var state: String?
        var contexts: Connection<CheckContextDTO>?

        var checks: CheckState? { state.flatMap(CheckState.init(rawValue:)) }

        /// The summary's state decides whether this is read: asked for with its contexts, GitHub reports some
        /// pending rollups as `FAILURE`, counting runs a newer push cancelled.
        var pendingChecks: PendingChecks? {
            guard let contexts else { return nil }
            var result = PendingChecks()
            for context in contexts.values {
                switch context.typename {
                case "CheckRun":
                    if let status = context.status, Self.runningStatuses.contains(status) {
                        result.running += 1
                    } else if context.status == "WAITING", let name = context.name {
                        result.waiting.append(WaitingCheck(name: name, url: context.detailsUrl, isApproval: true))
                    }
                case "StatusContext":
                    if context.state == "PENDING", let name = context.context {
                        result.waiting.append(
                            WaitingCheck(name: name, detail: context.description, url: context.targetUrl))
                    }
                default: break
                }
            }
            return result
        }
    }
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
