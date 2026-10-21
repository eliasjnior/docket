import Foundation

/// A pull request's review history, for `docket-cli stats` (`docs/01-product.md` §5). Read, computed, discarded.
public struct ReviewHistory: Hashable, Sendable {
    public var id: String
    public var author: String?
    public var mergedAt: Date?
    public var requests: [ReviewRequestEvent]
    public var reviews: [Review]

    public init(id: String, author: String?, mergedAt: Date?, requests: [ReviewRequestEvent], reviews: [Review]) {
        self.id = id
        self.author = author
        self.mergedAt = mergedAt
        self.requests = requests
        self.reviews = reviews
    }
}
