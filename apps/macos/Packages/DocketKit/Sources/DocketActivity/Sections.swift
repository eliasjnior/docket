import DocketCore
import Foundation

/// The popover's sections and their order (`docs/05-design.md` §5.3).
public struct Sections: Hashable, Sendable {
    public struct RepositoryGroup: Hashable, Sendable, Identifiable {
        public var repository: String
        public var items: [WatchedPullRequest]
        public var id: String { repository }
    }

    public var reviewRequested: [RepositoryGroup]
    public var mine: [WatchedPullRequest]
    public var involved: [WatchedPullRequest]
    public var ignored: [WatchedPullRequest]

    public var reviewRequestedCount: Int { reviewRequested.reduce(0) { $0 + $1.items.count } }

    public init(_ items: [WatchedPullRequest], tag: String? = nil, repository: String? = nil) {
        let filtered = items.filter { item in
            (tag.map { item.tags.contains($0) } ?? true)
                && (repository.map { item.pullRequest.repository.caseInsensitiveCompare($0) == .orderedSame } ?? true)
        }
        let active = filtered.filter { !$0.isIgnored }
        ignored = filtered.filter(\.isIgnored).sorted {
            ($0.ignoredAt ?? .distantPast) > ($1.ignoredAt ?? .distantPast)
        }

        let requested = active.filter { $0.role == .reviewRequested }.sorted(by: Self.longestWaitingFirst)
        let byRepository = Dictionary(grouping: requested) { $0.pullRequest.repository }
        reviewRequested = byRepository.map { RepositoryGroup(repository: $0.key, items: $0.value) }
            .sorted { lhs, rhs in
                let left = lhs.items.map(\.waitingSince).min() ?? .distantFuture
                let right = rhs.items.map(\.waitingSince).min() ?? .distantFuture
                if left != right { return left < right }
                return lhs.repository.lowercased() < rhs.repository.lowercased()
            }

        mine = active.filter { $0.role == .authored }.sorted { lhs, rhs in
            if lhs.status != rhs.status { return lhs.status < rhs.status }
            if lhs.pullRequest.createdAt != rhs.pullRequest.createdAt {
                return lhs.pullRequest.createdAt < rhs.pullRequest.createdAt
            }
            return Self.byReference(lhs, rhs)
        }
        involved = active.filter { $0.role == .involved }.sorted { lhs, rhs in
            if lhs.pullRequest.updatedAt != rhs.pullRequest.updatedAt {
                return lhs.pullRequest.updatedAt > rhs.pullRequest.updatedAt
            }
            return Self.byReference(lhs, rhs)
        }
    }

    private static func longestWaitingFirst(_ lhs: WatchedPullRequest, _ rhs: WatchedPullRequest) -> Bool {
        if lhs.waitingSince != rhs.waitingSince { return lhs.waitingSince < rhs.waitingSince }
        return byReference(lhs, rhs)
    }

    private static func byReference(_ lhs: WatchedPullRequest, _ rhs: WatchedPullRequest) -> Bool {
        let left = lhs.pullRequest.repository.lowercased()
        let right = rhs.pullRequest.repository.lowercased()
        return left != right ? left < right : lhs.pullRequest.number < rhs.pullRequest.number
    }
}
