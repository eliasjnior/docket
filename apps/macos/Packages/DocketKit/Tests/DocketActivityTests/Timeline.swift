import DocketActivity
import DocketCore
import DocketTestSupport
import Foundation

/// Polls in sequence over the same state, as the app runs them.
struct Timeline {
    var viewer = ViewerContext(login: "you", teams: ["acme": ["backend"]])
    var state = PersistedState()
    var cache: SnapshotCache?
    var config = Config()
    var now = Fixtures.now

    /// One poll. `discovery` defaults to: authored by you, requested when you are in `reviewRequests`, and
    /// involved for everything else listed.
    @discardableResult
    mutating func poll(
        _ pullRequests: [PullRequest], _ details: [PullRequestDetail] = [], involved: [String] = [],
        failed: [String] = []
    ) -> PollOutput {
        let discovery = Discovery(
            authored: pullRequests.filter { viewer.isYou($0.author?.login) }.map(\.id),
            requested: pullRequests.filter { !$0.reviewRequests.isEmpty }.map(\.id),
            commented: involved)
        let output = PollEngine.run(
            PollInput(
                viewer: viewer, now: now, timeZone: TimeZone(identifier: "America/Sao_Paulo") ?? .current,
                config: config, state: state, previousCache: cache, discovery: discovery,
                summaries: SummaryBatch(pullRequests: pullRequests, failed: failed),
                details: Dictionary(uniqueKeysWithValues: details.map { ($0.id, $0) })))
        state = output.state
        state.lastPoll = LastPoll(at: now, cost: 4, remaining: 4900, limit: 5000, resetAt: nil, serverTimeOffset: 0)
        cache = output.cache
        return output
    }

    mutating func advance(_ interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

extension PlannedNotification {
    var kind: EventKind? {
        if case .events(let kind, _) = content { return kind }
        return nil
    }

    var events: [Event] {
        if case .events(_, let events) = content { return events }
        return []
    }
}
