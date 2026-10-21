import Foundation

/// Who a review request is addressed to.
public enum Reviewer: Codable, Hashable, Sendable {
    case user(login: String)
    case team(organization: String, slug: String)

    /// `@ana` or `@acme/backend`.
    public var handle: String {
        switch self {
        case .user(let login): "@\(login)"
        case .team(let organization, let slug): "@\(organization)/\(slug)"
        }
    }
}
