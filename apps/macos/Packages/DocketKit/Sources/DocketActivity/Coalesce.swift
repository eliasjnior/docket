import DocketCore
import Foundation

/// Groups by repository and kind, then the cap of five (`docs/02-activity-detection.md` §7.1, §7.3).
public enum Coalesce {
    public static let cap = 5

    /// Highest first. A review group takes the rank of its most urgent decision.
    static func priority(of notification: PlannedNotification) -> Int {
        switch notification.content {
        case .events(let kind, let events): priority(of: kind, events: events)
        case .reminders: 6
        case .digest: 0
        case .overflow: 7
        }
    }

    private static func priority(of kind: EventKind, events: [Event]) -> Int {
        switch kind {
        case .reviewRequested: return 0
        case .reviewSubmitted:
            if events.contains(where: { $0.decision == .changesRequested }) { return 1 }
            if events.contains(where: { $0.decision == .approved }) { return 2 }
            return 4
        case .threadReply, .mention: return 3
        case .commentAdded: return 5
        case .checksFailed: return 1
        case .closedByOther: return 2
        }
    }

    static func oldest(_ notification: PlannedNotification) -> Date {
        switch notification.content {
        case .events(_, let events): events.map(\.at).min() ?? .distantFuture
        case .reminders(let reminders): reminders.map(\.requestedAt).min() ?? .distantFuture
        case .digest(let held): held.map(\.at).min() ?? .distantFuture
        case .overflow: .distantFuture
        }
    }

    static func size(_ notification: PlannedNotification) -> Int {
        switch notification.content {
        case .events(_, let events): events.count
        case .reminders(let reminders): reminders.count
        case .digest(let held): held.count
        case .overflow(let updates, _): updates
        }
    }

    public static func groups(events: [Event], reminders: [Reminder] = []) -> [PlannedNotification] {
        var groups: [PlannedNotification] = []
        // A review request is one notification per pull request: "@ana is waiting for your review".
        let byKey = Dictionary(grouping: events) { event in
            event.kind == .reviewRequested
                ? "\(event.pullRequestID)|\(event.kind.rawValue)"
                : "\(event.repository.lowercased())|\(event.kind.rawValue)"
        }
        for (_, members) in byKey {
            let sorted = members.sorted { $0.at < $1.at }
            guard let first = sorted.first else { continue }
            groups.append(PlannedNotification(repository: first.repository, content: .events(first.kind, sorted)))
        }
        for (_, members) in Dictionary(grouping: reminders, by: { $0.repository.lowercased() }) {
            let sorted = members.sorted { $0.requestedAt < $1.requestedAt }
            guard let first = sorted.first else { continue }
            groups.append(PlannedNotification(repository: first.repository, content: .reminders(sorted)))
        }
        return groups
    }

    /// At most five: the four most urgent, then `N more updates in M repositories`.
    public static func capped(_ groups: [PlannedNotification]) -> [PlannedNotification] {
        let ordered = groups.sorted { lhs, rhs in
            let left = priority(of: lhs)
            let right = priority(of: rhs)
            if left != right { return left < right }
            let leftOldest = oldest(lhs)
            let rightOldest = oldest(rhs)
            if leftOldest != rightOldest { return leftOldest < rightOldest }
            return (lhs.repository ?? "") < (rhs.repository ?? "")
        }
        guard ordered.count > cap else { return ordered }
        let kept = Array(ordered.prefix(cap - 1))
        let rest = ordered.dropFirst(cap - 1)
        let repositories = Set(rest.compactMap { $0.repository?.lowercased() }).count
        let overflow = PlannedNotification(
            repository: nil, content: .overflow(updates: rest.map(size).reduce(0, +), repositories: repositories))
        return kept + [overflow]
    }
}
