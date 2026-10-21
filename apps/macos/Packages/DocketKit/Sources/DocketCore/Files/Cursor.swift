import Foundation

/// What has been processed for one pull request (`docs/02-activity-detection.md` §5.1).
public struct Cursor: Codable, Hashable, Sendable {
    public static let seenLimit = 500

    public var ref: String
    public var role: Role?
    public var updatedAt: Date
    public var enteredAt: Date
    public var leftAt: Date?
    public var seen: [String]
    public var lastMergeable: Mergeable?
    /// The head commit whose failing checks were last notified (FR-61).
    public var notifiedFailingHead: String?

    public init(
        ref: String, role: Role?, updatedAt: Date, enteredAt: Date, leftAt: Date? = nil, seen: [String] = [],
        lastMergeable: Mergeable? = nil, notifiedFailingHead: String? = nil
    ) {
        self.ref = ref
        self.role = role
        self.updatedAt = updatedAt
        self.enteredAt = enteredAt
        self.leftAt = leftAt
        self.seen = seen
        self.lastMergeable = lastMergeable
        self.notifiedFailingHead = notifiedFailingHead
    }

    /// Adds `ids` not yet seen, dropping the oldest beyond the limit.
    public mutating func markSeen(_ ids: [String]) {
        let known = Set(seen)
        seen.append(contentsOf: ids.filter { !known.contains($0) })
        if seen.count > Self.seenLimit {
            seen.removeFirst(seen.count - Self.seenLimit)
        }
    }
}
