import DocketCore
import Foundation

/// The success metrics of `docs/01-product.md` §5, from your own review history. Nothing is stored.
public enum Stats {
    public struct Report: Hashable, Sendable {
        /// Median time from a review request to your first review after it.
        public var medianTimeToFirstReview: TimeInterval?
        public var answeredRequests: Int
        /// Requests you answered after more than two working days, or that are still waiting that long.
        public var requestsOlderThanTwoWorkingDays: Int
        /// Your merged pull requests whose last approval came more than 4 hours before the merge.
        public var approvedButUnmergedOverFourHours: Int
        public var mergedPullRequests: Int
    }

    public static func report(
        reviewed: [ReviewHistory], authored: [ReviewHistory], viewer: ViewerContext, now: Date, calendar: Calendar
    ) -> Report {
        var waits: [TimeInterval] = []
        var old = 0
        for history in reviewed {
            let mine = history.reviews.filter { viewer.isYou($0.author?.login) && $0.state != .pending }
                .compactMap(\.submittedAt).sorted()
            for request in history.requests where viewer.isAddressedToYou(request.reviewer) != false {
                let answer = mine.first { $0 > request.createdAt }
                let end = answer ?? now
                if answer != nil { waits.append(end.timeIntervalSince(request.createdAt)) }
                if workingDays(from: request.createdAt, to: end, calendar: calendar) > 2 { old += 1 }
            }
        }
        let merged = authored.filter { $0.mergedAt != nil }
        let slow = merged.filter { history in
            guard let mergedAt = history.mergedAt,
                let approved = history.reviews.filter({ $0.state == .approved }).compactMap(\.submittedAt)
                    .filter({ $0 <= mergedAt }).max()
            else { return false }
            return mergedAt.timeIntervalSince(approved) > 4 * 3600
        }
        return Report(
            medianTimeToFirstReview: median(waits), answeredRequests: waits.count,
            requestsOlderThanTwoWorkingDays: old, approvedButUnmergedOverFourHours: slow.count,
            mergedPullRequests: merged.count)
    }

    public static func median(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// Whole working days (Monday to Friday) between two instants.
    public static func workingDays(from start: Date, to end: Date, calendar: Calendar) -> Int {
        guard end > start else { return 0 }
        var days = 0
        var cursor = start
        while let next = calendar.date(byAdding: .day, value: 1, to: cursor), next <= end {
            if !calendar.isDateInWeekend(cursor) { days += 1 }
            cursor = next
        }
        return days
    }
}
