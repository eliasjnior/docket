import DocketCore
import Foundation

/// One bot test for the sub-tabs, seen state and notifications (spec §3).
public enum Bots {
    public static func isBot(_ actor: Actor?, extra: [String]) -> Bool {
        guard let actor else { return false }
        return actor.isAnyBot || listed(actor.login, extra)
    }

    public static func isBot(login: String, isBot: Bool, extra: [String]) -> Bool {
        isBot || login.hasSuffix("[bot]") || listed(login, extra)
    }

    public static func isBot(commit: CommitStamp, extra: [String]) -> Bool {
        guard let login = commit.login else { return commit.isBot }
        return isBot(login: login, isBot: commit.isBot, extra: extra)
    }

    private static func listed(_ login: String, _ extra: [String]) -> Bool {
        extra.contains { $0.caseInsensitiveCompare(login) == .orderedSame }
    }
}

/// When a human last did something on a pull request: a commit, a force push, a review, a comment or a request.
public enum HumanActivity {
    /// The latest stamp per actor in a detail read, bots included: they are judged when read.
    public static func stamps(in detail: PullRequestDetail) -> [ActivityStamp] {
        var latest: [String: ActivityStamp] = [:]
        func add(_ actor: Actor?, _ date: Date?) {
            guard let actor, let date else { return }
            let key = actor.login.lowercased()
            if let existing = latest[key], existing.at >= date { return }
            latest[key] = ActivityStamp(login: actor.login, isBot: actor.isBot, at: date)
        }
        for review in detail.reviews { add(review.author, review.submittedAt) }
        for comment in detail.comments { add(comment.author, comment.createdAt) }
        for comment in detail.threads.flatMap(\.comments) { add(comment.author, comment.createdAt) }
        for event in detail.requestEvents { add(event.actor, event.createdAt) }
        return latest.values.sorted { $0.login.lowercased() < $1.login.lowercased() }
    }

    /// The latest human activity, skipping `viewer` when given (for seen state: your own activity is not news).
    public static func last(_ cached: CachedPullRequest, excluding viewer: String? = nil, extra: [String]) -> Date? {
        func counts(_ login: String?) -> Bool {
            guard let viewer, let login else { return true }
            return login.caseInsensitiveCompare(viewer) != .orderedSame
        }
        var dates: [Date] = cached.activity.filter { stamp in
            !Bots.isBot(login: stamp.login, isBot: stamp.isBot, extra: extra) && counts(stamp.login)
        }.map(\.at)
        let pullRequest = cached.pullRequest
        if let commit = pullRequest.headCommit, !Bots.isBot(commit: commit, extra: extra), counts(commit.login) {
            dates.append(commit.at)
        }
        if let push = pullRequest.lastForcePush, !Bots.isBot(login: push.login, isBot: push.isBot, extra: extra),
            counts(push.login)
        {
            dates.append(push.at)
        }
        return dates.max()
    }
}
