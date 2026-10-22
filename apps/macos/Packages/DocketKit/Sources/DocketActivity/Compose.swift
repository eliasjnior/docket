import DocketCore
import Foundation

/// Who never notifies, then folding (`docs/02-activity-detection.md` §5.4–§5.5).
public enum Compose {
    /// §5.4 rules 1–3: you, bots outside the allowlist, pull requests muted with scope `all` or ignored.
    public static func filter(_ raw: [RawEvent], viewer: ViewerContext, config: Config) -> [RawEvent] {
        let allowlist = Set(config.botAllowlist.map { $0.lowercased() })
        return raw.filter { item in
            if viewer.isYou(item.author?.login) { return false }
            if let author = item.author, Bots.isBot(author, extra: config.triage.extraBotLogins),
                !allowlist.contains(author.login.lowercased())
            {
                return false
            }
            let id = item.event.pullRequestID
            if config.ignored[id] != nil || config.mutes[id]?.scope == .all { return false }
            return true
        }
    }

    /// §5.5: a review and its inline comments are one event; a reply-only review is replies; one reviewer's
    /// reviews in one poll fold into the latest.
    public static func fold(_ raw: [RawEvent]) -> [Event] {
        let replies = raw.filter { $0.event.kind == .threadReply }
        var reviews = raw.filter { $0.event.kind == .reviewSubmitted }
        var absorbed = Set<String>()

        // Rule 2: a `COMMENTED` review with no body whose every comment is a reply to you.
        reviews.removeAll { review in
            guard review.event.decision == .commented, review.bodyIsEmpty, let reviewID = review.reviewID else {
                return false
            }
            let ownReplies = replies.filter { $0.reviewID == reviewID }
            let allComments = raw.filter { $0.reviewID == reviewID && $0.event.kind != .reviewSubmitted }
            return !ownReplies.isEmpty && ownReplies.count == allComments.count
        }
        // Rule 3: per reviewer and pull request, the latest review only.
        var latest: [String: RawEvent] = [:]
        for review in reviews {
            let key = "\(review.event.pullRequestID)|\(review.event.actor?.lowercased() ?? "")"
            if let existing = latest[key], existing.event.at >= review.event.at { continue }
            latest[key] = review
        }
        let firedReviews = Set(reviews.compactMap(\.reviewID))
        // Rule 1: comments of a review that fired are part of it.
        for reply in replies where reply.reviewID.map(firedReviews.contains) == true {
            absorbed.insert(reply.event.id)
        }
        var events: [Event] = []
        for item in raw {
            switch item.event.kind {
            case .reviewSubmitted:
                let key = "\(item.event.pullRequestID)|\(item.event.actor?.lowercased() ?? "")"
                if latest[key]?.event.id == item.event.id { events.append(item.event) }
            case .threadReply:
                if !absorbed.contains(item.event.id) { events.append(item.event) }
            default:
                events.append(item.event)
            }
        }
        return events.sorted { $0.at < $1.at }
    }
}
