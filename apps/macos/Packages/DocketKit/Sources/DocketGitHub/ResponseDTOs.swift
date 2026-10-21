import DocketCore
import Foundation

struct Envelope<Payload: Decodable>: Decodable {
    var data: Payload?
    var errors: [GraphQLErrorDTO]?
}

struct GraphQLErrorDTO: Decodable {
    var type: String?
    var message: String?
    var path: [PathElement]?

    enum PathElement: Decodable, Equatable {
        case key(String)
        case index(Int)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let index = try? container.decode(Int.self) {
                self = .index(index)
            } else {
                self = .key(try container.decode(String.self))
            }
        }
    }

    /// The index into `nodes` this error is about, if any.
    var nodeIndex: Int? {
        guard let path, path.count >= 2, path[0] == .key("nodes"), case .index(let index) = path[1] else { return nil }
        return index
    }
}

struct RateLimitDTO: Decodable {
    var cost: Int
    var remaining: Int
    var limit: Int
    var resetAt: Date?

    var value: RateLimit { RateLimit(cost: cost, remaining: remaining, limit: limit, resetAt: resetAt) }
}

struct ActorDTO: Decodable {
    var typename: String?
    var login: String?

    enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case login
    }

    var value: Actor? { login.map { Actor(login: $0, isBot: typename == "Bot") } }
}

struct RequestedReviewerDTO: Decodable {
    struct Organization: Decodable { var login: String }

    var typename: String?
    var login: String?
    var slug: String?
    var organization: Organization?

    enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case login, slug, organization
    }

    var value: Reviewer? {
        if let login { return .user(login: login) }
        if let slug, let organization { return .team(organization: organization.login, slug: slug) }
        return nil
    }
}

struct Connection<Node: Decodable>: Decodable {
    var nodes: [Node?]?

    var values: [Node] { (nodes ?? []).compactMap { $0 } }
}

struct ViewerData: Decodable {
    struct Login: Decodable { var login: String }
    var viewer: Login
    var rateLimit: RateLimitDTO?
}

struct SearchPage: Decodable {
    struct PageInfo: Decodable {
        var hasNextPage: Bool
        var endCursor: String?
    }

    struct Node: Decodable {
        var id: String?
    }

    var issueCount: Int
    var pageInfo: PageInfo
    var nodes: [Node?]?
}

struct SearchData: Decodable {
    var authored: SearchPage?
    var requested: SearchPage?
    var commented: SearchPage?
    var reviewed: SearchPage?
    var rateLimit: RateLimitDTO?
}

struct NodesData<Node: Decodable>: Decodable {
    var nodes: [Node?]
    var rateLimit: RateLimitDTO?
}

struct TeamsData: Decodable {
    struct Organization: Decodable {
        struct Slug: Decodable { var slug: String }
        var teams: Connection<Slug>
    }

    var organization: Organization?
    var rateLimit: RateLimitDTO?
}

struct RepositoryData: Decodable {
    struct Repository: Decodable { var id: String }
    var repository: Repository?
    var rateLimit: RateLimitDTO?
}
