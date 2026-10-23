import DocketCore
import Foundation

/// A watched pull request with everything a row shows, derived from the cache, `config.json` and `state.json`.
public struct WatchedPullRequest: Hashable, Sendable, Identifiable {
    public var pullRequest: PullRequest
    public var role: Role
    public var status: Status
    /// What a `checksWaiting` status waits for.
    public var waitingChecks: [WaitingCheck]
    public var request: RequestInfo?
    public var reviewers: [ReviewerEntry]
    public var mute: Config.MuteEntry.Scope?
    public var ignoredAt: Date?
    public var isMarked: Bool
    /// Set for review requests only.
    public var triage: Triage?
    /// Never opened from Docket, or a human other than you acted on it since (spec §4).
    public var isUnseen: Bool
    /// The latest human activity, you included: a commit, a force push, a review, a comment or a request
    /// (`docs/02-activity-detection.md` §3.5). The lists are ordered by it.
    public var lastActivity: Date
    /// Set by the section that shows it, for a pull request in a stack (`Stacks`).
    public var stackPosition: StackPosition?
    /// Links in bots' comments, for `PR Links`; the description's are on `pullRequest.links`.
    public var botLinks: [PullRequestLink]

    public init(
        pullRequest: PullRequest, role: Role, status: Status, waitingChecks: [WaitingCheck] = [],
        request: RequestInfo? = nil,
        reviewers: [ReviewerEntry] = [], mute: Config.MuteEntry.Scope? = nil,
        ignoredAt: Date? = nil, isMarked: Bool = false, triage: Triage? = nil, isUnseen: Bool = false,
        lastActivity: Date? = nil, botLinks: [PullRequestLink] = []
    ) {
        self.pullRequest = pullRequest
        self.role = role
        self.status = status
        self.waitingChecks = waitingChecks
        self.request = request
        self.reviewers = reviewers
        self.mute = mute
        self.ignoredAt = ignoredAt
        self.isMarked = isMarked
        self.triage = triage
        self.isUnseen = isUnseen
        self.lastActivity = lastActivity ?? request?.requestedAt ?? pullRequest.createdAt
        self.botLinks = botLinks
    }

    public var id: String { pullRequest.id }
    public var isIgnored: Bool { ignoredAt != nil }
    /// Start of the waited time of a review request (FR-33).
    public var waitingSince: Date { request?.requestedAt ?? pullRequest.createdAt }
}

public enum Watch {
    public static func isUnseen(_ cached: CachedPullRequest, config: Config, state: PersistedState) -> Bool {
        guard let seenAt = state.seen[cached.id] else { return true }
        let others = HumanActivity.last(
            cached, excluding: state.viewerLogin, extra: config.triage.extraBotLogins)
        return others.map { $0 > seenAt } ?? false
    }

    /// The rows for the cached summaries, with the selection applied (FR-74).
    public static func items(cache: [CachedPullRequest], config: Config, state: PersistedState, now: Date)
        -> [WatchedPullRequest]
    {
        let marked = Set(state.marked)
        return cache.compactMap { cached in
            let pullRequest = cached.pullRequest
            guard config.selection.watches(pullRequest.repository) else { return nil }
            let status = StatusRules.status(
                of: pullRequest, lastMergeable: state.cursors[pullRequest.id]?.lastMergeable)
            let ignored = config.ignored[pullRequest.id]
            return WatchedPullRequest(
                pullRequest: pullRequest, role: cached.role, status: status,
                waitingChecks: status == .checksWaiting ? StatusRules.waitingChecks(pullRequest) : [],
                request: cached.role == .reviewRequested ? cached.request : nil,
                reviewers: cached.role == .authored
                    ? Reviewers.entries(for: pullRequest, commenters: cached.commenters) : [],
                mute: ignored == nil ? config.mutes[pullRequest.id]?.scope : nil,
                ignoredAt: ignored?.ignoredAt,
                isMarked: ignored == nil && marked.contains(pullRequest.id),
                triage: cached.role == .reviewRequested ? Triage.of(cached, config: config, now: now) : nil,
                isUnseen: ignored == nil && isUnseen(cached, config: config, state: state),
                lastActivity: HumanActivity.last(cached, extra: config.triage.extraBotLogins),
                botLinks: cached.botLinks
            )
        }
    }
}
