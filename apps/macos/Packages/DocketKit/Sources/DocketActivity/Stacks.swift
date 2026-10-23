import DocketCore
import Foundation

/// Pull requests stacked on one another: one whose base branch is another's head branch, in the same repository
/// (`docs/02-activity-detection.md` §3.7).
public struct Stack: Hashable, Sendable, Identifiable {
    public var repository: String
    /// From the bottom, the one that merges into a branch no pull request here has, to the top.
    public var items: [WatchedPullRequest]

    public init(repository: String, items: [WatchedPullRequest]) {
        self.repository = repository
        self.items = items
    }

    /// `stack:` and the bottom pull request's ID, which a row of the same list already uses.
    public var id: String { "stack:" + (items.first?.id ?? repository) }
    /// The branch the bottom pull request merges into, such as `main`.
    public var base: String? { items.first?.pullRequest.baseRefName }
    public var lastActivity: Date { items.map(\.lastActivity).max() ?? .distantPast }
    /// When the oldest pull request in it was opened: the stack's age.
    public var createdAt: Date { items.map(\.pullRequest.createdAt).min() ?? .distantPast }
    /// The status that needs you first, in the precedence order of §3.2.
    public var status: Status? { items.map(\.status).min() }
    /// Lines added and deleted, and files changed, across the stack; `nil` until every count is known.
    public var additions: Int? { total(\.additions) }
    public var deletions: Int? { total(\.deletions) }
    public var changedFiles: Int? { total(\.changedFiles) }

    /// No human activity on any pull request in it for `staleAfterDays`, as in §3.6.
    public func isStale(now: Date, staleAfterDays: Int) -> Bool {
        now.timeIntervalSince(lastActivity) > TimeInterval(staleAfterDays) * 86400
    }

    private func total(_ count: KeyPath<PullRequest, Int?>) -> Int? {
        let counts = items.map { $0.pullRequest[keyPath: count] }
        guard !counts.contains(nil) else { return nil }
        return counts.compactMap { $0 }.reduce(0, +)
    }
}

/// Where a row sits in its stack, for the `2/3` badge.
public struct StackPosition: Hashable, Sendable {
    public var index: Int
    public var count: Int

    public init(index: Int, count: Int) {
        self.index = index
        self.count = count
    }
}

public enum Stacks {
    /// Every stack of two or more among `items`. A pull request with two stacked on it keeps both, the lower
    /// number first. Stacks come in the order of their first row in `items`.
    public static func find(_ items: [WatchedPullRequest]) -> [Stack] {
        func key(_ repository: String, _ branch: String) -> String { "\(repository.lowercased())\u{0}\(branch)" }
        var byHead: [String: WatchedPullRequest] = [:]
        for item in items {
            guard let head = item.pullRequest.headRefName else { continue }
            byHead[key(item.pullRequest.repository, head)] = item
        }
        func parent(_ item: WatchedPullRequest) -> WatchedPullRequest? {
            guard let base = item.pullRequest.baseRefName,
                let found = byHead[key(item.pullRequest.repository, base)], found.id != item.id
            else { return nil }
            return found
        }
        var children: [String: [WatchedPullRequest]] = [:]
        for item in items {
            if let parent = parent(item) { children[parent.id, default: []].append(item) }
        }
        var placed: Set<String> = []
        var stacks: [Stack] = []
        for item in items where !placed.contains(item.id) {
            var root = item
            var seen: Set<String> = [root.id]
            while let up = parent(root), seen.insert(up.id).inserted { root = up }
            var ordered: [WatchedPullRequest] = []
            var pending = [root]
            while let next = pending.popLast() {
                guard placed.insert(next.id).inserted else { continue }
                ordered.append(next)
                let kids = (children[next.id] ?? []).sorted { $0.pullRequest.number < $1.pullRequest.number }
                pending.append(contentsOf: kids.reversed())
            }
            if ordered.count > 1 { stacks.append(Stack(repository: root.pullRequest.repository, items: ordered)) }
        }
        return stacks
    }

    /// `items` with each stack's rows together, bottom to top, where its first row was, and their positions set.
    public static func arrange(_ items: [WatchedPullRequest]) -> [WatchedPullRequest] {
        let stacks = find(items)
        guard !stacks.isEmpty else { return items }
        var stackOf: [String: Stack] = [:]
        for stack in stacks { for item in stack.items { stackOf[item.id] = stack } }
        var emitted: Set<String> = []
        var result: [WatchedPullRequest] = []
        for item in items {
            guard let stack = stackOf[item.id] else {
                result.append(item)
                continue
            }
            guard emitted.insert(stack.id).inserted else { continue }
            result.append(contentsOf: positioned(stack))
        }
        return result
    }

    /// The stack's rows with their `2/3` positions.
    public static func positioned(_ stack: Stack) -> [WatchedPullRequest] {
        stack.items.enumerated().map { index, item in
            var item = item
            item.stackPosition = StackPosition(index: index + 1, count: stack.items.count)
            return item
        }
    }
}
