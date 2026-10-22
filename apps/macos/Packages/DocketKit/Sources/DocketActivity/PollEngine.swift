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
        summaries: [PullRequest], discovery: Discovery, state: PersistedState, viewer: ViewerContext, now: Date,
        previousCache: SnapshotCache? = nil
    ) -> [String] {
        let unread = Set((previousCache?.pullRequests ?? []).filter { !$0.activityRead }.map(\.id))
        return summaries.filter { pullRequest in
            let cursor = state.cursors[pullRequest.id]
            // One last read of your own pull request as it closes, to learn who closed it (FR-62).
            if cursor?.role == .authored, pullRequest.state != .open { return true }
            let candidate = Candidate(
                pullRequest: pullRequest, detail: nil, hits: DiscoveryHits(discovery, id: pullRequest.id),
                previous: cursor)
            let mayHaveRole =
                Roles.role(of: candidate, viewer: viewer, now: now) != nil
                || pullRequest.reviewRequests.contains { if case .team = $0 { true } else { false } }
            guard mayHaveRole, pullRequest.state == .open, !pullRequest.isArchived else { return false }
            guard let cursor, cursor.role != nil else { return true }
            return cursor.updatedAt != pullRequest.updatedAt || unread.contains(pullRequest.id)
        }.map(\.id)
    }

    public static func run(_ input: PollInput) -> PollOutput {
        var run = PollRun(input: input)
        for pullRequest in input.summaries.pullRequests {
            run.observe(pullRequest)
        }
        run.keepFailed()
        run.markLeft()
        run.endStaleHold()
        if run.isBaseline { run.state.baselineAt = input.now }
        run.seenBaseline()
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
    /// Closed this poll: kept in `watchedIDs` only so their event survives the mark filter.
    var closing = Set<String>()
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
        if previous?.role == .authored, pullRequest.state != .open, !isBaseline {
            closed(pullRequest, detail: detail)
        }
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
        checksFailed(pullRequest, role: role, cursor: &cursor, entering: entering)
        state.cursors[pullRequest.id] = cursor
        cached.append(cachedEntry(pullRequest, role: role, detail: detail))
    }

    /// `checksFailed`: once per failing head commit, recorded without notifying on entry (FR-61).
    private mutating func checksFailed(_ pullRequest: PullRequest, role: Role, cursor: inout Cursor, entering: Bool) {
        guard role == .authored, pullRequest.checks == .failure || pullRequest.checks == .error,
            let head = pullRequest.headOID, head != cursor.notifiedFailingHead
        else { return }
        cursor.notifiedFailingHead = head
        guard !entering, !isBaseline else { return }
        let event = Event(
            kind: .checksFailed, itemID: "\(pullRequest.id):\(head)", pullRequestID: pullRequest.id,
            repository: pullRequest.repository, number: pullRequest.number, title: pullRequest.title,
            url: pullRequest.url.appending(path: "checks"), actor: nil, at: input.now)
        raw.append(RawEvent(event: event, author: nil))
    }

    /// `closedByOther`: your pull request merged or closed by someone else (FR-62).
    private mutating func closed(_ pullRequest: PullRequest, detail: PullRequestDetail?) {
        let merged = pullRequest.state == .merged
        guard let closer = merged ? pullRequest.mergedBy : detail?.closedBy else { return }
        var event = Event(
            kind: .closedByOther, itemID: "\(pullRequest.id):\(pullRequest.state.rawValue)",
            pullRequestID: pullRequest.id, repository: pullRequest.repository, number: pullRequest.number,
            title: pullRequest.title, url: pullRequest.url, actor: closer, at: input.now)
        event.merged = merged
        raw.append(RawEvent(event: event, author: Actor(login: closer)))
        watchedIDs.insert(pullRequest.id)
        closing.insert(pullRequest.id)
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
        let activity = detail.map(HumanActivity.stamps(in:)) ?? old?.activity ?? []
        return CachedPullRequest(
            pullRequest: pullRequest, role: role, request: request, commenters: commenters, activity: activity,
            activityRead: detail != nil || old?.activityRead == true)
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
    static let holdLimit: TimeInterval = 12 * 3600

    /// A hold that started 12 hours ago ends by itself: macOS may never say the Focus ended (§7.5).
    mutating func endStaleHold() {
        if let hold = state.focusHold, input.now.timeIntervalSince(hold.since) >= Self.holdLimit {
            state.focusHold = nil
        }
    }

    /// Once the hold is over: one digest per repository, dropping pull requests muted, ignored or gone.
    private mutating func digest() -> [PlannedNotification] {
        guard !state.held.isEmpty else { return [] }
        let config = input.config
        let kept = state.held.filter { held in
            watchedIDs.contains(held.nodeID) && config.ignored[held.nodeID] == nil
                && config.mutes[held.nodeID]?.scope != .all
        }
        state.held = []
        let byRepository = Dictionary(grouping: kept) { $0.repository.lowercased() }
        return byRepository.values.compactMap { events in
            guard let first = events.first else { return nil }
            return PlannedNotification(repository: first.repository, content: .digest(events.sorted { $0.at < $1.at }))
        }
    }

    /// Filter, fold, the ledger, marks, the per-kind switches, then groups and the cap (§5.4–§7.3).
    mutating func compose() -> [PlannedNotification] {
        let now = input.now
        let excluded = Triage.silenced(cached, config: input.config, now: now)
        let filtered = Compose.filter(raw, viewer: input.viewer, config: input.config).filter { item in
            item.event.kind != .reviewRequested || !excluded.contains(item.event.pullRequestID)
        }
        let folded = Compose.fold(filtered).filter { state.delivered[$0.id] == nil }
        events = Compose.fold(raw)
        let marked = Set(state.marked).union(folded.map(\.pullRequestID))
        state.marked = marked.filter { watchedIDs.contains($0) && !closing.contains($0) }.sorted()
        let enabled = folded.filter { input.config.notifications.isEnabled($0.kind) }
        let newlyRequested = Set(raw.filter { $0.event.kind == .reviewRequested }.map(\.event.pullRequestID))
        let reminders = Reminders.due(
            cached, records: &state.reminders,
            context: Reminders.Context(
                now: now, timeZone: input.timeZone, config: input.config, isBaseline: isBaseline,
                newlyRequested: newlyRequested, holding: state.focusHold != nil, excluded: excluded))
        for event in enabled {
            state.delivered[event.id] = now
        }
        state.delivered = state.delivered.filter { now.timeIntervalSince($0.value) <= Self.ledgerRetention }
        if state.focusHold != nil {
            // Held, not delivered: the digest says it when the Focus ends (§7.5).
            state.held.append(contentsOf: enabled.map(HeldEvent.init))
            if state.held.count > PersistedState.heldLimit {
                state.held.removeFirst(state.held.count - PersistedState.heldLimit)
            }
            return []
        }
        let digests = digest()
        return Coalesce.capped(digests + Coalesce.groups(events: enabled, reminders: reminders))
    }

    /// The first poll with seen state marks everything listed as seen, so an upgrade does not light up every row.
    mutating func seenBaseline() {
        guard state.seenBaselineAt == nil else { return }
        for entry in cached { state.seen[entry.id] = input.now }
        state.seenBaselineAt = input.now
    }

    mutating func markLeft() {
        for (id, cursor) in state.cursors where cursor.role != nil && (!watchedIDs.contains(id) || closing.contains(id))
        {
            var left = cursor
            left.role = nil
            left.leftAt = input.now
            state.cursors[id] = left
        }
        state.marked.removeAll { !watchedIDs.contains($0) }
    }
}
