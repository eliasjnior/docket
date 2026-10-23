import DocketActivity
import DocketCore
import Foundation

/// The VoiceOver template of `docs/05-design.md` §11, with empty clauses left out.
enum RowAccessibility {
    static func label(for item: WatchedPullRequest, placement: RowView.Placement, now: Date) -> String {
        let pullRequest = item.pullRequest
        var parts: [String] = []
        var status = item.status.label
        if pullRequest.isDraft { status += ", " + String(localized: "draft", comment: "VoiceOver: draft modifier") }
        parts.append(status + ".")
        parts.append(pullRequest.title + ".")
        parts.append(
            String(
                localized: "\(pullRequest.repository) number \(pullRequest.number).", comment: "VoiceOver: reference"))
        parts.append(timeClause(item, placement: placement, now: now))
        parts.append(
            String(
                localized: "Last activity \(spoken(now.timeIntervalSince(item.lastActivity))) ago.",
                comment: "VoiceOver: time since the last human activity"))
        if let team = item.request?.team {
            parts.append(
                String(localized: "Requested from team \(spokenHandle(team.handle)).", comment: "VoiceOver: team"))
        }
        if placement != .mine, let author = pullRequest.author?.login {
            parts.append(String(localized: "By \(author).", comment: "VoiceOver: author"))
        }
        if let additions = pullRequest.additions, let deletions = pullRequest.deletions {
            parts.append(
                String(
                    localized: "\(additions) lines added, \(deletions) deleted.", comment: "VoiceOver: size"))
        }
        if let reviewers = reviewersClause(item) { parts.append(reviewers) }
        if !pullRequest.labels.isEmpty {
            let names = pullRequest.labels.map(\.name).joined(separator: ", ")
            parts.append(String(localized: "Labels: \(names).", comment: "VoiceOver: GitHub labels"))
        }
        if item.mute == .all { parts.append(String(localized: "Muted.", comment: "VoiceOver: muted")) }
        if item.isUnseen { parts.append(String(localized: "Unseen.", comment: "VoiceOver: unseen row")) }
        return parts.joined(separator: " ")
    }

    private static func timeClause(_ item: WatchedPullRequest, placement: RowView.Placement, now: Date) -> String {
        if placement == .reviewRequested {
            let elapsed = now.timeIntervalSince(item.waitingSince)
            return String(localized: "Waiting for review for \(spoken(elapsed))", comment: "VoiceOver: waited time")
                + style(elapsed) + "."
        }
        let elapsed = now.timeIntervalSince(item.pullRequest.createdAt)
        return String(localized: "Open for \(spoken(elapsed))", comment: "VoiceOver: age") + style(elapsed) + "."
    }

    private static func reviewersClause(_ item: WatchedPullRequest) -> String? {
        guard !item.reviewers.isEmpty else { return nil }
        let reviewers = item.reviewers.map { entry in
            let login = spokenHandle(entry.handle)
            switch entry.state {
            case .approved: return String(localized: "\(login) approved", comment: "VoiceOver: reviewer")
            case .changesRequested:
                return String(localized: "\(login) requested changes", comment: "VoiceOver: reviewer")
            case .pending: return String(localized: "\(login) pending", comment: "VoiceOver: reviewer")
            case .commented: return String(localized: "\(login) commented", comment: "VoiceOver: reviewer")
            }
        }
        return String(localized: "Reviewers: \(reviewers.joined(separator: ", ")).", comment: "VoiceOver: reviewers")
    }

    /// `4 days`, never `4d`.
    static func spoken(_ elapsed: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = elapsed >= 14 * 86400 ? [.weekOfMonth] : [.day, .hour, .minute]
        return formatter.string(from: max(60, elapsed)) ?? ""
    }

    private static func style(_ elapsed: TimeInterval) -> String {
        switch Age.style(elapsed) {
        case .normal: ""
        case .ageing: ", " + String(localized: "ageing", comment: "VoiceOver: over 3 days")
        case .stale: ", " + String(localized: "stale", comment: "VoiceOver: over 7 days")
        }
    }

    private static func spokenHandle(_ handle: String) -> String {
        handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
    }
}
