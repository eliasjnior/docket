import DocketCore
import Foundation

/// The popover's filters (spec §6): OR within a dimension, AND across them, names compared case-insensitively.
public struct PopoverFilter: Hashable, Sendable {
    public enum Dimension: String, CaseIterable, Hashable, Sendable {
        case organization
        case repository
        case label
        case status
    }

    public var organizations: Set<String>
    public var repositories: Set<String>
    public var labels: Set<String>
    public var statuses: Set<Status>
    /// The dimensions in the order they were first set, so `Escape` clears the latest.
    public private(set) var order: [Dimension] = []

    public init(
        organizations: Set<String> = [], repositories: Set<String> = [], labels: Set<String> = [],
        statuses: Set<Status> = []
    ) {
        self.organizations = Set(organizations.map { $0.lowercased() })
        self.repositories = Set(repositories.map { $0.lowercased() })
        self.labels = Set(labels.map { $0.lowercased() })
        self.statuses = statuses
        order = Dimension.allCases.filter { !isEmpty($0) }
    }

    public var isEmpty: Bool { Dimension.allCases.allSatisfy(isEmpty) }

    public func isEmpty(_ dimension: Dimension) -> Bool {
        switch dimension {
        case .organization: organizations.isEmpty
        case .repository: repositories.isEmpty
        case .label: labels.isEmpty
        case .status: statuses.isEmpty
        }
    }

    public func contains(_ value: String, in dimension: Dimension) -> Bool {
        switch dimension {
        case .organization: organizations.contains(value.lowercased())
        case .repository: repositories.contains(value.lowercased())
        case .label: labels.contains(value.lowercased())
        case .status: Status(rawValue: value).map(statuses.contains) ?? false
        }
    }

    /// Adds `value` when absent, removes it when present.
    public mutating func toggle(_ value: String, in dimension: Dimension) {
        let key = value.lowercased()
        switch dimension {
        case .organization: organizations.formSymmetricDifference([key])
        case .repository: repositories.formSymmetricDifference([key])
        case .label: labels.formSymmetricDifference([key])
        case .status: if let status = Status(rawValue: value) { statuses.formSymmetricDifference([status]) }
        }
        updateOrder(dimension)
    }

    public mutating func clear(_ dimension: Dimension) {
        switch dimension {
        case .organization: organizations = []
        case .repository: repositories = []
        case .label: labels = []
        case .status: statuses = []
        }
        updateOrder(dimension)
    }

    /// `Escape`: the most recently added dimension. Returns false when nothing was set.
    @discardableResult
    public mutating func clearLatest() -> Bool {
        guard let latest = order.last else { return false }
        clear(latest)
        return true
    }

    public func matches(_ item: WatchedPullRequest) -> Bool {
        let pullRequest = item.pullRequest
        if !organizations.isEmpty, !organizations.contains(pullRequest.owner.lowercased()) { return false }
        if !repositories.isEmpty, !repositories.contains(pullRequest.repository.lowercased()) { return false }
        if !labels.isEmpty, !pullRequest.labels.contains(where: { labels.contains($0.name.lowercased()) }) {
            return false
        }
        if !statuses.isEmpty, !statuses.contains(item.status) { return false }
        return true
    }

    private mutating func updateOrder(_ dimension: Dimension) {
        order.removeAll { $0 == dimension }
        if !isEmpty(dimension) { order.append(dimension) }
    }
}

/// The three groups of *Mine* (spec §7), in display order.
public enum MineKind: String, CaseIterable, Hashable, Sendable {
    case ready
    case blocked
    case draft

    public static let blockingStatuses: Set<Status> = [.conflict, .checksFailing, .changesRequested]

    public static func of(_ item: WatchedPullRequest) -> MineKind {
        if item.pullRequest.isDraft { return .draft }
        return blockingStatuses.contains(item.status) ? .blocked : .ready
    }
}
