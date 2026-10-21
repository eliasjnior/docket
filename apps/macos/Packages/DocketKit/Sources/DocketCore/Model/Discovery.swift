import Foundation

/// The node IDs the four searches returned (`docs/02-activity-detection.md` §2.1).
public struct Discovery: Codable, Hashable, Sendable {
    public var authored: [String]
    public var requested: [String]
    public var commented: [String]
    public var reviewed: [String]
    /// Results beyond the 150 that are read, per search alias.
    public var notShown: [String: Int]

    public init(
        authored: [String] = [], requested: [String] = [], commented: [String] = [], reviewed: [String] = [],
        notShown: [String: Int] = [:]
    ) {
        self.authored = authored
        self.requested = requested
        self.commented = commented
        self.reviewed = reviewed
        self.notShown = notShown
    }

    public var allIDs: [String] {
        var seen = Set<String>()
        return (authored + requested + commented + reviewed).filter { seen.insert($0).inserted }
    }
}
