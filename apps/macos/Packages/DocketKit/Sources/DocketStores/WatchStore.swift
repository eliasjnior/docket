import DocketActivity
import DocketCore
import Foundation
import Observation

/// What the popover and the status item show, derived from the last poll and `config.json`.
@MainActor
@Observable
public final class WatchStore {
    public private(set) var snapshot = WatchSnapshot()
    @ObservationIgnored private let configStore: ConfigStore

    public init(configStore: ConfigStore) {
        self.configStore = configStore
    }

    public func apply(_ snapshot: WatchSnapshot) {
        self.snapshot = snapshot
    }

    public var config: Config { configStore.config }
    public var account: AccountState { snapshot.account }
    public var problem: PollProblem? { snapshot.problem }
    public var isPolling: Bool { snapshot.isPolling }
    public var fetchedAt: Date? { snapshot.cache?.fetchedAt }
    public var hasCache: Bool { snapshot.cache != nil }

    public var items: [WatchedPullRequest] {
        Watch.items(cache: snapshot.cache?.pullRequests ?? [], config: config, state: snapshot.state)
    }

    public var count: Int { Count.count(items, settings: config.count) }

    public func sections(tag: String? = nil, repository: String? = nil) -> Sections {
        Sections(items, tag: tag, repository: repository)
    }

    /// Tags in use, most used first (FR-82, FR-83).
    public var tagsInUse: [String] {
        Tags.inUse(config.tags.values.map(\.tags))
    }

    public func notShown(_ role: Role) -> Int {
        let alias: String =
            switch role {
            case .authored: "authored"
            case .reviewRequested: "requested"
            case .involved: "commented"
            }
        return snapshot.cache?.notShown[alias] ?? 0
    }

    /// Older than two poll intervals (FR-44).
    public func isStale(now: Date) -> Bool {
        guard let fetchedAt else { return false }
        return now.timeIntervalSince(fetchedAt) > TimeInterval(2 * config.polling.intervalSeconds)
    }
}
