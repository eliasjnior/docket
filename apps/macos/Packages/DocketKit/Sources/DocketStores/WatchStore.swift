import DocketActivity
import DocketCore
import Foundation
import Observation

/// What the popover and the status item show, derived from the last poll and `config.json`.
@MainActor
@Observable
public final class WatchStore {
    public private(set) var snapshot = WatchSnapshot() {
        didSet { version += 1 }
    }
    @ObservationIgnored public let configStore: ConfigStore
    @ObservationIgnored private let now: @Sendable () -> Date
    /// Bumped with each snapshot, so the derived rows are kept until something they come from changes.
    @ObservationIgnored private var version = 0
    /// The rows and the sections per filter, computed once per snapshot, `config.json` and minute: every
    /// view of the popover, and every row's context menu, asked for them on each redraw.
    @ObservationIgnored private var derived: Derived?

    private struct Derived {
        var version: Int
        var config: Config
        var minute: Int
        var items: [WatchedPullRequest]
        var sections: [PopoverFilter: Sections] = [:]
    }

    public init(configStore: ConfigStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.configStore = configStore
        self.now = now
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

    public var items: [WatchedPullRequest] { current().items }

    public var count: Int { Count.count(items, settings: config.count, triage: config.triage) }

    public func sections(filter: PopoverFilter = PopoverFilter()) -> Sections {
        var derived = current()
        if let sections = derived.sections[filter] { return sections }
        let sections = Sections(derived.items, filter: filter, conflictedDrafts: config.conflictedDrafts)
        derived.sections[filter] = sections
        self.derived = derived
        return sections
    }

    /// The rows for the current snapshot, `config.json` and minute: the minute because a pull request turns
    /// stale with time alone. Reading `snapshot` and `config` keeps the views observing them.
    private func current() -> Derived {
        let snapshot = snapshot
        let config = config
        let now = now().addingTimeInterval(snapshot.state.lastPoll?.serverTimeOffset ?? 0)
        let minute = Int(now.timeIntervalSince1970 / 60)
        if let derived, derived.version == version, derived.minute == minute, derived.config == config {
            return derived
        }
        let fresh = Derived(
            version: version, config: config, minute: minute,
            items: Watch.items(
                cache: snapshot.cache?.pullRequests ?? [], config: config, state: snapshot.state, now: now))
        derived = fresh
        return fresh
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
