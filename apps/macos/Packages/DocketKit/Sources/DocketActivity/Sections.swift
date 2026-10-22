import DocketCore
import Foundation

/// The popover's sections and their order (`docs/05-design.md` §5.3).
public struct Sections: Hashable, Sendable {
    public struct RepositoryGroup: Hashable, Sendable, Identifiable {
        public var repository: String
        public var items: [WatchedPullRequest]
        public var id: String { repository }
    }

    public struct MineGroup: Hashable, Sendable, Identifiable {
        public var kind: MineKind
        public var items: [WatchedPullRequest]
        public var id: MineKind { kind }
    }

    public var reviewRequested: [RepositoryGroup]
    /// Ready, then blocked, then drafts; empty groups left out.
    public var mineGroups: [MineGroup]
    public var involved: [WatchedPullRequest]
    public var ignored: [WatchedPullRequest]

    public var mine: [WatchedPullRequest] { mineGroups.flatMap(\.items) }
    public var reviewRequestedCount: Int { reviewRequested.reduce(0) { $0 + $1.items.count } }

    /// The review requests of one sub-tab, still grouped by repository in the same order.
    public func reviewRequested(_ triage: Triage) -> [RepositoryGroup] {
        reviewRequested.compactMap { group in
            let items = group.items.filter { $0.triage == triage }
            return items.isEmpty ? nil : RepositoryGroup(repository: group.repository, items: items)
        }
    }

    public var triageCounts: [Triage: Int] {
        Dictionary(grouping: reviewRequested.flatMap(\.items), by: { $0.triage ?? .humans }).mapValues(\.count)
    }

    public init(
        _ items: [WatchedPullRequest], filter: PopoverFilter = PopoverFilter(), tag: String? = nil,
        repository: String? = nil
    ) {
        let filtered = items.filter { item in
            filter.matches(item) && (tag.map { item.tags.contains($0) } ?? true)
                && (repository.map { item.pullRequest.repository.caseInsensitiveCompare($0) == .orderedSame } ?? true)
        }
        let active = filtered.filter { !$0.isIgnored }
        ignored = filtered.filter(\.isIgnored).sorted {
            ($0.ignoredAt ?? .distantPast) > ($1.ignoredAt ?? .distantPast)
        }

        let requested = active.filter { $0.role == .reviewRequested }.sorted(by: Self.newestFirst)
        let byRepository = Dictionary(grouping: requested) { $0.pullRequest.repository }
        reviewRequested = byRepository.map { RepositoryGroup(repository: $0.key, items: $0.value) }
            .sorted { lhs, rhs in
                let left = lhs.items.map(\.waitingSince).max() ?? .distantPast
                let right = rhs.items.map(\.waitingSince).max() ?? .distantPast
                if left != right { return left > right }
                return lhs.repository.lowercased() < rhs.repository.lowercased()
            }

        let mine = active.filter { $0.role == .authored }.sorted { lhs, rhs in
            if lhs.status != rhs.status { return lhs.status < rhs.status }
            if lhs.pullRequest.createdAt != rhs.pullRequest.createdAt {
                return lhs.pullRequest.createdAt > rhs.pullRequest.createdAt
            }
            return Self.byReference(lhs, rhs)
        }
        let byKind = Dictionary(grouping: mine, by: MineKind.of)
        mineGroups = MineKind.allCases.compactMap { kind in
            byKind[kind].map { MineGroup(kind: kind, items: $0) }
        }
        involved = active.filter { $0.role == .involved }.sorted { lhs, rhs in
            if lhs.pullRequest.updatedAt != rhs.pullRequest.updatedAt {
                return lhs.pullRequest.updatedAt > rhs.pullRequest.updatedAt
            }
            return Self.byReference(lhs, rhs)
        }
    }

    private static func newestFirst(_ lhs: WatchedPullRequest, _ rhs: WatchedPullRequest) -> Bool {
        if lhs.waitingSince != rhs.waitingSince { return lhs.waitingSince > rhs.waitingSince }
        return byReference(lhs, rhs)
    }

    private static func byReference(_ lhs: WatchedPullRequest, _ rhs: WatchedPullRequest) -> Bool {
        let left = lhs.pullRequest.repository.lowercased()
        let right = rhs.pullRequest.repository.lowercased()
        return left != right ? left < right : lhs.pullRequest.number < rhs.pullRequest.number
    }
}
