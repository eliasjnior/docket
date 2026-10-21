import DocketCore
import Foundation

struct HistoryData: Decodable {
    struct Search: Decodable {
        var pageInfo: SearchPage.PageInfo
        var nodes: [HistoryNode?]?
    }

    var search: Search
    var rateLimit: RateLimitDTO?
}

struct HistoryNode: Decodable {
    struct Item: Decodable {
        var typename: String
        var id: String?
        var createdAt: Date?
        var submittedAt: Date?
        var state: String?
        var actor: ActorDTO?
        var author: ActorDTO?
        var requestedReviewer: RequestedReviewerDTO?

        enum CodingKeys: String, CodingKey {
            case typename = "__typename"
            case id, createdAt, submittedAt, state, actor, author, requestedReviewer
        }
    }

    var id: String?
    var mergedAt: Date?
    var author: ActorDTO?
    var timelineItems: Connection<Item>?

    var value: ReviewHistory? {
        guard let id else { return nil }
        let items = timelineItems?.values ?? []
        return ReviewHistory(
            id: id, author: author?.login, mergedAt: mergedAt,
            requests: items.compactMap { item in
                guard item.typename == "ReviewRequestedEvent", let id = item.id, let at = item.createdAt else {
                    return nil
                }
                return ReviewRequestEvent(
                    id: id, createdAt: at, actor: item.actor?.value, reviewer: item.requestedReviewer?.value)
            },
            reviews: items.compactMap { item in
                guard item.typename == "PullRequestReview", let id = item.id else { return nil }
                return Review(
                    id: id, state: ReviewState(rawValue: item.state ?? "") ?? .commented, submittedAt: item.submittedAt,
                    author: item.author?.value)
            })
    }
}

extension GraphQLClient {
    /// Pull requests matching `query` with their review requests and reviews, up to 300.
    public func history(query: String) async throws -> GitHubResponse<[ReviewHistory]> {
        var histories: [ReviewHistory] = []
        var after: String?
        var metas: [ResponseMeta] = []
        for _ in 0..<6 {
            let response = try await historyPage(query: query, after: after)
            histories.append(contentsOf: response.value.0)
            metas.append(response.meta)
            guard let next = response.value.1 else { break }
            after = next
        }
        return GitHubResponse(value: histories, meta: ResponseMeta.combine(metas))
    }

    private func historyPage(query: String, after: String?) async throws -> GitHubResponse<([ReviewHistory], String?)> {
        let (envelope, meta) = try await send(
            Queries.history, ["query": .string(query), "after": after.map(GraphQLValue.string) ?? .null],
            as: HistoryData.self)
        guard let data = envelope.data else { throw GitHubError.invalidResponse("history") }
        let page = data.search.pageInfo
        return GitHubResponse(
            value: ((data.search.nodes ?? []).compactMap { $0?.value }, page.hasNextPage ? page.endCursor : nil),
            meta: meta.with(data.rateLimit))
    }
}
