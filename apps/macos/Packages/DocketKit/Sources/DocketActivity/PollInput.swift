import DocketCore
import Foundation

/// Everything one poll read, plus what was saved before it (`docs/02-activity-detection.md` §1).
public struct PollInput: Sendable {
    public var viewer: ViewerContext
    /// The Mac's clock corrected by the server offset (§3.4).
    public var now: Date
    public var timeZone: TimeZone
    public var config: Config
    public var state: PersistedState
    public var previousCache: SnapshotCache?
    public var discovery: Discovery
    public var summaries: SummaryBatch
    public var details: [String: PullRequestDetail]

    public init(
        viewer: ViewerContext, now: Date, timeZone: TimeZone = .current, config: Config = Config(),
        state: PersistedState = PersistedState(), previousCache: SnapshotCache? = nil,
        discovery: Discovery = Discovery(), summaries: SummaryBatch = SummaryBatch(),
        details: [String: PullRequestDetail] = [:]
    ) {
        self.viewer = viewer
        self.now = now
        self.timeZone = timeZone
        self.config = config
        self.state = state
        self.previousCache = previousCache
        self.discovery = discovery
        self.summaries = summaries
        self.details = details
    }
}

/// What a poll decided: the files to commit, then the notifications to hand to macOS (§5.6).
public struct PollOutput: Sendable {
    public var state: PersistedState
    public var cache: SnapshotCache
    public var notifications: [PlannedNotification]
    /// Every event the diff produced, before filtering, for logging search lag (NFR-04).
    public var events: [Event]

    public init(state: PersistedState, cache: SnapshotCache, notifications: [PlannedNotification], events: [Event]) {
        self.state = state
        self.cache = cache
        self.notifications = notifications
        self.events = events
    }
}
