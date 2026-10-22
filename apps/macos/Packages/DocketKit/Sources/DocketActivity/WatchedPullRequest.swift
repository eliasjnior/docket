import DocketCore
import Foundation

/// A watched pull request with everything a row shows, derived from the cache, `config.json` and `state.json`.
public struct WatchedPullRequest: Hashable, Sendable, Identifiable {
    public var pullRequest: PullRequest
    public var role: Role
    public var status: Status
    public var request: RequestInfo?
    public var reviewers: [ReviewerEntry]
    public var tags: [String]
    public var mute: Config.MuteEntry.Scope?
    public var ignoredAt: Date?
    public var isMarked: Bool
    /// Set for review requests only.
    public var triage: Triage?

    public init(
        pullRequest: PullRequest, role: Role, status: Status, request: RequestInfo? = nil,
        reviewers: [ReviewerEntry] = [], tags: [String] = [], mute: Config.MuteEntry.Scope? = nil,
        ignoredAt: Date? = nil, isMarked: Bool = false, triage: Triage? = nil
    ) {
        self.pullRequest = pullRequest
        self.role = role
        self.status = status
        self.request = request
        self.reviewers = reviewers
        self.tags = tags
        self.mute = mute
        self.ignoredAt = ignoredAt
        self.isMarked = isMarked
        self.triage = triage
    }

    public var id: String { pullRequest.id }
    public var isIgnored: Bool { ignoredAt != nil }
    /// Start of the waited time of a review request (FR-33).
    public var waitingSince: Date { request?.requestedAt ?? pullRequest.createdAt }
}

public enum Watch {
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
                request: cached.role == .reviewRequested ? cached.request : nil,
                reviewers: cached.role == .authored
                    ? Reviewers.entries(for: pullRequest, commenters: cached.commenters) : [],
                tags: config.tags[pullRequest.id]?.tags ?? [],
                mute: ignored == nil ? config.mutes[pullRequest.id]?.scope : nil,
                ignoredAt: ignored?.ignoredAt,
                isMarked: ignored == nil && marked.contains(pullRequest.id),
                triage: cached.role == .reviewRequested ? Triage.of(cached, config: config, now: now) : nil
            )
        }
    }
}
