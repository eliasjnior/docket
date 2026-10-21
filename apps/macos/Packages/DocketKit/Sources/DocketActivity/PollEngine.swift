import DocketCore
import Foundation

/// One poll as a pure function: previous state and what GitHub said in, new state and notifications out.
public enum PollEngine {
    public static let cursorRetention: TimeInterval = 30 * 86400
    public static let knownRepositoryRetention: TimeInterval = 90 * 86400

    /// The IDs to summarize: every candidate, and every pull request already in the watch set (§1 step 2).
    public static func summaryIDs(discovery: Discovery, state: PersistedState) -> [String] {
        var ids = discovery.allIDs
        var seen = Set(ids)
        for (id, cursor) in state.cursors.sorted(by: { $0.key < $1.key }) where cursor.role != nil {
            if seen.insert(id).inserted { ids.append(id) }
        }
        return ids
    }

    /// The pull requests whose details are read: entering the watch set, or changed since (§1 step 4).
    public static func detailIDs(
        summaries: [PullRequest], discovery: Discovery, state: PersistedState, viewer: ViewerContext, now: Date
    ) -> [String] {
        summaries.filter { pullRequest in
            let cursor = state.cursors[pullRequest.id]
            let candidate = Candidate(
                pullRequest: pullRequest, detail: nil, hits: DiscoveryHits(discovery, id: pullRequest.id),
                previous: cursor)
            let mayHaveRole =
                Roles.role(of: candidate, viewer: viewer, now: now) != nil
                || pullRequest.reviewRequests.contains { if case .team = $0 { true } else { false } }
            guard mayHaveRole, pullRequest.state == .open, !pullRequest.isArchived else { return false }
            guard let cursor, cursor.role != nil else { return true }
            return cursor.updatedAt != pullRequest.updatedAt
        }.map(\.id)
    }

    public static func run(_ input: PollInput) -> PollOutput {
        var run = PollRun(input: input)
        for pullRequest in input.summaries.pullRequests {
            run.observe(pullRequest)
        }
        run.keepFailed()
        run.markLeft()
        if run.isBaseline { run.state.baselineAt = input.now }
        let notifications = run.compose()
        let cache = SnapshotCache(
            fetchedAt: input.now, viewerLogin: input.viewer.login, pullRequests: run.cached,
            knownRepositories: knownRepositories(input, now: input.now), notShown: input.discovery.notShown)
        return PollOutput(state: run.state, cache: cache, notifications: notifications, events: run.events)
    }

    private static func knownRepositories(_ input: PollInput, now: Date) -> [KnownRepository] {
        var known = Dictionary(
            (input.previousCache?.knownRepositories ?? []).map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first })
        for pullRequest in input.summaries.pullRequests {
            known[pullRequest.repository.lowercased()] = KnownRepository(name: pullRequest.repository, lastSeenAt: now)
        }
        return known.values.filter { now.timeIntervalSince($0.lastSeenAt) <= knownRepositoryRetention }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}

/// The working state of one `PollEngine.run`.
struct PollRun {
    let input: PollInput
    let isBaseline: Bool
    let previousCache: [String: CachedPullRequest]
    var state: PersistedState
    var cached: [CachedPullRequest] = []
    var watchedIDs = Set<String>()
    var raw: [RawEvent] = []
    var events: [Event] = []

    init(input: PollInput) {
        self.input = input
        state = input.state
        isBaseline = input.state.baselineAt == nil
        previousCache = Dictionary(
            (input.previousCache?.pullRequests ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    mutating func observe(_ pullRequest: PullRequest) {
        let now = input.now
        let previous = state.cursors[pullRequest.id]
        let detail = input.details[pullRequest.id]
        let candidate = Candidate(
            pullRequest: pullRequest, detail: detail, hits: DiscoveryHits(input.discovery, id: pullRequest.id),
            previous: previous)
        guard let role = Roles.role(of: candidate, viewer: input.viewer, now: now),
            input.config.selection.watches(pullRequest.repository)
        else { return }
        watchedIDs.insert(pullRequest.id)

        let entering = previous?.role == nil
        var cursor = Cursor(ref: pullRequest.ref, role: role, updatedAt: pullRequest.updatedAt, enteredAt: now)
        if let previous {
            if entering {
                // Back within the retention window: keep what was already seen.
                cursor.seen = previous.seen
                cursor.lastMergeable = previous.lastMergeable
            } else {
                cursor = previous
            }
        }
        if let detail {
            let subject = DiffSubject(
                pullRequest: pullRequest, role: role, detail: detail, cursor: cursor, entering: entering,
                isBaseline: isBaseline, previousPollAt: input.state.lastPoll?.at)
            raw.append(contentsOf: Diff.events(for: subject, viewer: input.viewer))
            cursor.markSeen(detail.itemIDs)
            cursor.updatedAt = pullRequest.updatedAt
        }
        cursor.ref = pullRequest.ref
        cursor.role = role
        cursor.leftAt = nil
        if pullRequest.mergeable != .unknown { cursor.lastMergeable = pullRequest.mergeable }
        state.cursors[pullRequest.id] = cursor
        cached.append(cachedEntry(pullRequest, role: role, detail: detail))
    }

    private func cachedEntry(_ pullRequest: PullRequest, role: Role, detail: PullRequestDetail?) -> CachedPullRequest {
        let old = previousCache[pullRequest.id]
        let viewer = input.viewer
        var request: RequestInfo?
        if role == .reviewRequested {
            request =
                detail.map { Requests.latest(on: pullRequest, detail: $0, viewer: viewer) }
                ?? old?.request ?? Requests.latest(on: pullRequest, detail: nil, viewer: viewer)
        }
        let commenters =
            detail.map { Reviewers.commenters(in: $0, pullRequest: pullRequest, viewer: viewer) }
            ?? old?.commenters ?? []
        return CachedPullRequest(pullRequest: pullRequest, role: role, request: request, commenters: commenters)
    }

    /// A node that failed this poll keeps its previous snapshot (`docs/02-activity-detection.md` §9).
    mutating func keepFailed() {
        for id in input.summaries.failed where !watchedIDs.contains(id) {
            if let old = previousCache[id], state.cursors[id]?.role != nil {
                watchedIDs.insert(id)
                cached.append(old)
            }
        }
    }

    static let ledgerRetention: TimeInterval = 14 * 86400

    /// Filter, fold, the ledger, marks, the per-kind switches, then groups and the cap (§5.4–§7.3).
    mutating func compose() -> [PlannedNotification] {
        let now = input.now
        let filtered = Compose.filter(raw, viewer: input.viewer, config: input.config)
        let folded = Compose.fold(filtered).filter { state.delivered[$0.id] == nil }
        events = Compose.fold(raw)
        let marked = Set(state.marked).union(folded.map(\.pullRequestID))
        state.marked = marked.filter(watchedIDs.contains).sorted()
        let enabled = folded.filter { input.config.notifications.isEnabled($0.kind) }
        let notifications = Coalesce.capped(Coalesce.groups(events: enabled))
        for event in enabled {
            state.delivered[event.id] = now
        }
        state.delivered = state.delivered.filter { now.timeIntervalSince($0.value) <= Self.ledgerRetention }
        return notifications
    }

    mutating func markLeft() {
        for (id, cursor) in state.cursors where cursor.role != nil && !watchedIDs.contains(id) {
            var left = cursor
            left.role = nil
            left.leftAt = input.now
            state.cursors[id] = left
        }
        state.marked.removeAll { !watchedIDs.contains($0) }
    }
}
