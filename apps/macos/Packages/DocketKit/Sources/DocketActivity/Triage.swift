import DocketCore
import Foundation

/// The sub-tabs of *Review requested* (`docs/02-activity-detection.md` §3.6), in display order. Every request is
/// in exactly one.
public enum Triage: String, CaseIterable, Hashable, Sendable {
    case humans
    case bots
    case drafts
    case stale

    /// A draft first: its author said it is not ready. Then stale: no human activity for `staleAfterDays`,
    /// counting the pull request's creation. Then bots.
    public static func of(_ cached: CachedPullRequest, config: Config, now: Date) -> Triage {
        let settings = config.triage
        let pullRequest = cached.pullRequest
        if pullRequest.isDraft { return .drafts }
        let last = max(
            HumanActivity.last(cached, extra: settings.extraBotLogins) ?? .distantPast, pullRequest.createdAt)
        if now.timeIntervalSince(last) >= TimeInterval(settings.staleAfterDays) * 86400 { return .stale }
        return Bots.isBot(pullRequest.author, extra: settings.extraBotLogins) ? .bots : .humans
    }

    /// Left out of the menu bar count.
    public static func isExcluded(_ triage: Triage, settings: Config.Triage) -> Bool {
        switch triage {
        case .humans: false
        case .bots: !settings.countBots
        case .drafts: !settings.countDrafts
        case .stale: !settings.countStale
        }
    }

    /// No review-request notification and no reminder. Bots have their own switch, silent by default; drafts
    /// and stale pull requests follow their count switch.
    public static func isSilenced(_ triage: Triage, settings: Config.Triage) -> Bool {
        triage == .bots ? !settings.notifyBots : isExcluded(triage, settings: settings)
    }

    /// The review requests whose triage is silenced, for one poll.
    public static func silenced(_ cached: [CachedPullRequest], config: Config, now: Date) -> Set<String> {
        Set(
            cached.filter { entry in
                entry.role == .reviewRequested
                    && isSilenced(of(entry, config: config, now: now), settings: config.triage)
            }.map(\.id))
    }
}
