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
    /// Ready, then blocked, then drafts; empty groups left out. Every pull request of yours, stacked or not: the
    /// board and the count read these.
    public var mineGroups: [MineGroup]
    /// Your stacks, the latest activity first.
    public var mineStacks: [Stack]
    /// The list's status groups: like `mineGroups`, but each stack kept whole, bottom to top, in the group of
    /// `kind(of:)`.
    public var mineListGroups: [MineGroup]
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
        _ items: [WatchedPullRequest], filter: PopoverFilter = PopoverFilter(),
        conflictedDrafts: Config.ConflictedDrafts = .draft
    ) {
        let filtered = items.filter(filter.matches)
        let active = filtered.filter { !$0.isIgnored }
        ignored = filtered.filter(\.isIgnored).sorted {
            ($0.ignoredAt ?? .distantPast) > ($1.ignoredAt ?? .distantPast)
        }

        let requested = active.filter { $0.role == .reviewRequested }.sorted(by: Self.latestActivityFirst)
        let byRepository = Dictionary(grouping: requested) { $0.pullRequest.repository }
        reviewRequested = byRepository.map { RepositoryGroup(repository: $0.key, items: Stacks.arrange($0.value)) }
            .sorted { lhs, rhs in
                let left = lhs.items.map(\.lastActivity).max() ?? .distantPast
                let right = rhs.items.map(\.lastActivity).max() ?? .distantPast
                if left != right { return left > right }
                return lhs.repository.lowercased() < rhs.repository.lowercased()
            }

        var mine = active.filter { $0.role == .authored }.sorted(by: Self.latestActivityFirst)
        let stacks = Stacks.find(mine).map { Stack(repository: $0.repository, items: Stacks.positioned($0)) }
            .sorted { $0.lastActivity > $1.lastActivity }
        let positions: [String: StackPosition] = Dictionary(
            stacks.flatMap(\.items).compactMap { item in item.stackPosition.map { (item.id, $0) } },
            uniquingKeysWith: { first, _ in first })
        for index in mine.indices { mine[index].stackPosition = positions[mine[index].id] }
        mineStacks = stacks
        let byKind = Dictionary(grouping: mine) { MineKind.of($0, conflictedDrafts: conflictedDrafts) }
        mineGroups = MineKind.allCases.compactMap { kind in
            byKind[kind].map { MineGroup(kind: kind, items: $0) }
        }
        // The list keeps a stack whole, as a block among the rows of one group, placed by its latest activity.
        let stackKinds = Dictionary(
            stacks.map { ($0.id, Self.kind(of: $0, conflictedDrafts: conflictedDrafts)) },
            uniquingKeysWith: { a, _ in a })
        mineListGroups = MineKind.allCases.compactMap { kind in
            let singles = (byKind[kind] ?? []).filter { $0.stackPosition == nil }.map { [$0] }
            let blocks = stacks.filter { stackKinds[$0.id] == kind }.map(\.items)
            let units = (singles + blocks).sorted { lhs, rhs in
                let left = lhs.map(\.lastActivity).max() ?? .distantPast
                let right = rhs.map(\.lastActivity).max() ?? .distantPast
                return left != right ? left > right : Self.byReference(lhs[0], rhs[0])
            }
            return units.isEmpty ? nil : MineGroup(kind: kind, items: units.flatMap { $0 })
        }
        involved = Stacks.arrange(active.filter { $0.role == .involved }.sorted(by: Self.latestActivityFirst))
    }

    /// Rows split by repository, keeping their order: a repository comes where its first row was, so the one
    /// with the latest activity leads (a *Mine* board column, `docs/05-design.md` §5.3).
    public static func byRepository(_ items: [WatchedPullRequest]) -> [RepositoryGroup] {
        var order: [String] = []
        var rows: [String: [WatchedPullRequest]] = [:]
        for item in items {
            let repository = item.pullRequest.repository
            if rows[repository] == nil { order.append(repository) }
            rows[repository, default: []].append(item)
        }
        return order.map { RepositoryGroup(repository: $0, items: rows[$0] ?? []) }
    }

    /// The *Mine* group a whole stack goes to in the list: Blocked when any of it is, else Ready when any of it is
    /// not a draft, else Draft.
    public static func kind(of stack: Stack, conflictedDrafts: Config.ConflictedDrafts = .draft) -> MineKind {
        let kinds = Set(stack.items.map { MineKind.of($0, conflictedDrafts: conflictedDrafts) })
        if kinds.contains(.blocked) { return .blocked }
        return kinds.contains(.ready) ? .ready : .draft
    }

    /// What moved last comes first, in every list (`docs/05-design.md` §5.3).
    private static func latestActivityFirst(_ lhs: WatchedPullRequest, _ rhs: WatchedPullRequest) -> Bool {
        if lhs.lastActivity != rhs.lastActivity { return lhs.lastActivity > rhs.lastActivity }
        return byReference(lhs, rhs)
    }

    private static func byReference(_ lhs: WatchedPullRequest, _ rhs: WatchedPullRequest) -> Bool {
        let left = lhs.pullRequest.repository.lowercased()
        let right = rhs.pullRequest.repository.lowercased()
        return left != right ? left < right : lhs.pullRequest.number < rhs.pullRequest.number
    }
}
