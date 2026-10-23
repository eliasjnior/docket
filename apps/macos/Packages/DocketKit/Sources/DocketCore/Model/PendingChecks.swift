import Foundation

/// What a `PENDING` or `EXPECTED` rollup is made of (`docs/02-activity-detection.md` §3.1): check runs still
/// running, and the pending commit statuses and approvals that may be waiting for a person.
public struct PendingChecks: Codable, Hashable, Sendable {
    /// Check runs queued or in progress.
    public var running: Int
    public var waiting: [WaitingCheck]

    public init(running: Int = 0, waiting: [WaitingCheck] = []) {
        self.running = running
        self.waiting = waiting
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        running = c.value(.running, default: 0)
        waiting = c.value(.waiting, default: [])
    }
}

/// A pending commit status, or a check run waiting for an approval.
public struct WaitingCheck: Codable, Hashable, Sendable {
    public var name: String
    /// The status's description, which usually says what it waits for.
    public var detail: String?
    public var url: URL?
    /// A check run `WAITING` for an environment's reviewers, rather than a commit status.
    public var isApproval: Bool

    public init(name: String, detail: String? = nil, url: URL? = nil, isApproval: Bool = false) {
        self.name = name
        self.detail = detail
        self.url = url
        self.isApproval = isApproval
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        detail = c.value(.detail, default: nil)
        url = c.value(.url, default: nil)
        isApproval = c.value(.isApproval, default: false)
    }
}
