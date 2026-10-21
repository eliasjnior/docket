import DocketActivity
import DocketCore
import Foundation
import os

public typealias Storage = CacheStoring & ConfigStoring & StateStoring

/// Runs polls one at a time and commits them before delivering (`docs/03-architecture.md` §4–§5).
public actor Poller {
    public typealias Publish = @Sendable (WatchSnapshot) async -> Void

    static let teamRefresh: TimeInterval = 3600
    static let viewerRecheck: TimeInterval = 3600

    private let github: GitHubSource
    private let tokens: TokenProvider
    private let storage: Storage
    private let notifications: NotificationSink
    private let clock: Clock
    private let timeZone: @Sendable () -> TimeZone
    private let jitter: @Sendable () -> Double
    private let log = Logger(subsystem: "com.eliasjnior.docket", category: "poll")

    private var publish: Publish?
    private var loop: Task<Void, Never>?
    private var snapshot = WatchSnapshot()
    private var viewerLogin: String?
    private var viewerCheckedAt: Date?
    private var isOnline = true
    private var networkFailures = 0
    private var suspendedUntil: Date?
    private var lastSuccessAt: Date?

    public init(
        github: GitHubSource, tokens: TokenProvider, storage: Storage, notifications: NotificationSink,
        clock: Clock = SystemClock(), timeZone: @escaping @Sendable () -> TimeZone = { .current },
        jitter: @escaping @Sendable () -> Double = { Double.random(in: 0.9...1.1) }
    ) {
        self.github = github
        self.tokens = tokens
        self.storage = storage
        self.notifications = notifications
        self.clock = clock
        self.timeZone = timeZone
        self.jitter = jitter
    }

    // MARK: - Lifecycle

    /// Publishes the cached snapshot at once (FR-44), then polls on the interval.
    public func start(publish: @escaping Publish) async {
        self.publish = publish
        let state = (try? await storage.loadState()) ?? PersistedState()
        var cache = await storage.loadCache()
        if let cached = cache, cached.viewerLogin != state.viewerLogin { cache = nil }
        snapshot = WatchSnapshot(cache: cache, state: state, account: .loading)
        lastSuccessAt = cache?.fetchedAt
        await publish(snapshot)
        startLoop()
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    public func willSleep() {
        stop()
    }

    /// One poll on wake (FR-95), then the interval again.
    public func didWake() {
        startLoop()
    }

    public func setOnline(_ online: Bool) async {
        let wasOnline = isOnline
        isOnline = online
        if !online {
            snapshot.problem = .offline
            await emit()
        } else if !wasOnline {
            networkFailures = 0
            await pollNow()
        }
    }

    /// A poll now, unless one is running: a request during a poll is dropped, not queued (§6.3).
    @discardableResult
    public func pollNow() async -> Bool {
        guard !snapshot.isPolling else { return false }
        _ = await poll()
        return true
    }

    /// A poll now if the last one is older than `age` — for the popover opening (§6.3).
    public func pollIfOlder(than age: TimeInterval) async {
        if let lastSuccessAt, clock.now().timeIntervalSince(lastSuccessAt) < age { return }
        await pollNow()
    }

    /// Bookkeeping that is not a poll: the popover opened, a hold started. Serialized with polls.
    public func updateState(_ mutate: @Sendable (inout PersistedState) -> Void) async {
        var state = (try? await storage.loadState()) ?? snapshot.state
        mutate(&state)
        do {
            try await storage.saveState(state)
        } catch {
            log.error("Could not save state: \(String(describing: error), privacy: .public)")
        }
        snapshot.state = state
        await emit()
    }

    public func current() -> WatchSnapshot { snapshot }

    /// A Focus filter turned holding on or off (`docs/02-activity-detection.md` §7.5). Ending a hold polls at
    /// once, and that poll delivers the digest.
    public func setHold(_ holding: Bool) async {
        let now = clock.now()
        await updateState { state in
            if holding {
                if state.focusHold == nil { state.focusHold = FocusHold(since: now) }
            } else {
                state.focusHold = nil
            }
        }
        if !holding { await pollNow() }
    }

    /// Retention over `state.json` (`docs/04-data.md` §4); returns `config` with dead tags, mutes and ignores
    /// removed, for the config store to save.
    public func retain(
        config: Config, prune: @Sendable (Config, PersistedState, Set<String>, Date) -> (Config, PersistedState)
    )
        async -> Config
    {
        let state = (try? await storage.loadState()) ?? snapshot.state
        let watched = Set(snapshot.cache?.pullRequests.map(\.id) ?? [])
        let (pruned, prunedState) = prune(config, state, watched, clock.now())
        if prunedState != state {
            try? await storage.saveState(prunedState)
            snapshot.state = prunedState
            await emit()
        }
        return pruned
    }

    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = await self?.poll() else { return }
                do {
                    try await self?.clock.sleep(for: delay)
                } catch {
                    return
                }
            }
        }
    }

    // MARK: - One poll

    /// Runs one poll and returns the delay before the next.
    private func poll() async -> TimeInterval {
        let config = (try? await storage.loadConfig()) ?? Config()
        let interval = TimeInterval(config.polling.intervalSeconds) * jitter()
        guard !snapshot.isPolling else { return interval }
        guard isOnline else {
            snapshot.problem = .offline
            await emit()
            return interval
        }
        if let suspendedUntil, clock.now() < suspendedUntil {
            snapshot.problem = .rateLimited(until: suspendedUntil)
            await emit()
            return suspendedUntil.timeIntervalSince(clock.now())
        }
        snapshot.isPolling = true
        await emit()
        let delay: TimeInterval
        do {
            let rateLimit = try await runPoll(config: config)
            networkFailures = 0
            suspendedUntil = Backoff.suspendedUntil(rateLimit)
            snapshot.problem = suspendedUntil.map { PollProblem.rateLimited(until: $0) }
            delay = Backoff.delay(after: rateLimit, interval: interval, now: clock.now())
        } catch {
            delay = handle(error, interval: interval)
        }
        snapshot.isPolling = false
        await emit()
        return delay
    }

    private func handle(_ error: Error, interval: TimeInterval) -> TimeInterval {
        log.error("Poll failed: \(String(describing: error), privacy: .public)")
        switch error {
        case TokenError.ghNotFound:
            snapshot.account = .ghNotFound
        case TokenError.signedOut, TokenError.timedOut, GitHubError.unauthorized:
            snapshot.account = .signedOut
            viewerLogin = nil
        case GitHubError.missingScopes(let scopes):
            snapshot.account = .missingScopes(scopes)
            viewerLogin = nil
        case GitHubError.secondaryRateLimit(let retryAfter):
            snapshot.problem = .rateLimited(until: clock.now().addingTimeInterval(retryAfter))
            return retryAfter
        case GitHubError.rateLimited(let resetAt):
            let until = resetAt ?? clock.now().addingTimeInterval(interval)
            suspendedUntil = until
            snapshot.problem = .rateLimited(until: until)
            return max(1, until.timeIntervalSince(clock.now()))
        case GitHubError.network:
            snapshot.problem = .failed(at: lastSuccessAt ?? clock.now())
            let retry = Backoff.networkRetries[safe: networkFailures] ?? interval
            networkFailures += 1
            return retry
        default:
            snapshot.problem = .failed(at: lastSuccessAt ?? clock.now())
        }
        return interval
    }

    /// Steps 1–8 of `docs/02-activity-detection.md` §1. Returns the last rate limit seen.
    private func runPoll(config: Config) async throws -> RateLimit? {
        var metas: [ResponseMeta] = []
        let login = try await currentViewer(metas: &metas)
        var state = (try? await storage.loadState()) ?? PersistedState()
        var cache = await storage.loadCache()
        if state.viewerLogin?.lowercased() != login.lowercased() {
            // `gh auth switch`: the cursors belong to someone else (`docs/04-data.md` §2.2).
            state = PersistedState(viewerLogin: login)
            cache = nil
        }

        let started = clock.now()
        let discovery = try await github.discover(login: login, since: started.addingTimeInterval(-30 * 86400))
        metas.append(discovery.meta)
        let summaryIDs = PollEngine.summaryIDs(discovery: discovery.value, state: state)
        let summaries =
            summaryIDs.isEmpty
            ? GitHubResponse(value: SummaryBatch()) : try await github.summaries(ids: summaryIDs)
        metas.append(summaries.meta)
        await refreshTeams(for: summaries.value.pullRequests, login: login, state: &state, metas: &metas)

        let viewer = ViewerContext(login: login, teams: teams(in: state))
        let detailIDs = PollEngine.detailIDs(
            summaries: summaries.value.pullRequests, discovery: discovery.value, state: state, viewer: viewer,
            now: started)
        let details = detailIDs.isEmpty ? GitHubResponse(value: []) : try await github.details(ids: detailIDs)
        metas.append(details.meta)

        let meta = Self.combine(metas)
        let offset = meta.serverDate.map { $0.timeIntervalSince(clock.now()) } ?? 0
        let now = clock.now().addingTimeInterval(offset)
        let output = PollEngine.run(
            PollInput(
                viewer: viewer, now: now, timeZone: timeZone(), config: config, state: state, previousCache: cache,
                discovery: discovery.value, summaries: summaries.value,
                details: Dictionary(details.value.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })))

        var newState = output.state
        newState.viewerLogin = login
        newState.unauthorizedOwners = meta.samlOrganizations
        if let rateLimit = meta.rateLimit {
            newState.lastPoll = LastPoll(
                at: now, cost: rateLimit.cost, remaining: rateLimit.remaining, limit: rateLimit.limit,
                resetAt: rateLimit.resetAt, serverTimeOffset: offset)
        }
        try await storage.saveState(newState)
        try await storage.saveCache(output.cache)
        await notifications.deliver(output.notifications)

        logPoll(output: output, meta: meta, started: started, watched: output.cache.pullRequests.count)
        lastSuccessAt = now
        snapshot.cache = output.cache
        snapshot.state = newState
        snapshot.account = .ready
        snapshot.samlOrganizations = Self.samlOrganizations(meta)
        return meta.rateLimit
    }

    private func currentViewer(metas: inout [ResponseMeta]) async throws -> String {
        if let viewerLogin, let checked = viewerCheckedAt, clock.now().timeIntervalSince(checked) < Self.viewerRecheck {
            return viewerLogin
        }
        if viewerCheckedAt != nil {
            // `gh auth switch` leaves the old token valid, so re-read it hourly (`docs/03-architecture.md` §6).
            _ = try await tokens.refresh()
        }
        let viewer = try await github.viewer()
        metas.append(viewer.meta)
        viewerLogin = viewer.value.login
        viewerCheckedAt = clock.now()
        return viewer.value.login
    }

    private func refreshTeams(
        for pullRequests: [PullRequest], login: String, state: inout PersistedState, metas: inout [ResponseMeta]
    ) async {
        var organizations = Set<String>()
        for pullRequest in pullRequests {
            for case .team(let organization, _) in pullRequest.reviewRequests {
                organizations.insert(organization.lowercased())
            }
        }
        for organization in organizations.sorted() {
            if let cached = state.teams[organization],
                clock.now().timeIntervalSince(cached.fetchedAt) < Self.teamRefresh
            {
                continue
            }
            guard let response = try? await github.teams(organization: organization, login: login) else { continue }
            metas.append(response.meta)
            state.teams[organization] = TeamCache(slugs: response.value, fetchedAt: clock.now())
        }
    }

    private func teams(in state: PersistedState) -> [String: Set<String>] {
        state.teams.reduce(into: [:]) { result, entry in
            result[entry.key.lowercased()] = Set(entry.value.slugs.map { $0.lowercased() })
        }
    }

    private func logPoll(output: PollOutput, meta: ResponseMeta, started: Date, watched: Int) {
        let duration = clock.now().timeIntervalSince(started)
        let cost = meta.rateLimit?.cost ?? 0
        let remaining = meta.rateLimit?.remaining ?? 0
        log.info("Poll: \(watched) watched, \(output.events.count) events, cost \(cost), remaining \(remaining)")
        log.info(
            "Poll delivered \(output.notifications.count) notifications in \(duration, format: .fixed(precision: 2)) s")
        for event in output.events {
            // Search lag (NFR-04): how long after the event it was discovered.
            let lag = started.timeIntervalSince(event.at)
            let kind = event.kind.rawValue
            log.info("\(kind, privacy: .public) discovered \(lag, format: .fixed(precision: 0)) s after it happened")
        }
    }

    private func emit() async {
        await publish?(snapshot)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
