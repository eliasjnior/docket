import DocketCore
import Foundation

/// When the next poll runs (`docs/02-activity-detection.md` §6.3).
enum Backoff {
    static let networkRetries: [TimeInterval] = [15, 30, 60]

    /// `nil` means poll at the normal interval.
    static func delay(after rateLimit: RateLimit?, interval: TimeInterval, now: Date) -> TimeInterval {
        guard let rateLimit, rateLimit.limit > 0 else { return interval }
        let share = Double(rateLimit.remaining) / Double(rateLimit.limit)
        let untilReset = rateLimit.resetAt.map { max(0, $0.timeIntervalSince(now)) } ?? interval
        if share < 0.2 { return max(untilReset, interval) }
        if share < 0.3 { return interval * 2 }
        return interval
    }

    /// The pause NFR-03 imposes: no poll at all while `remaining` is under 20% of `limit`.
    static func suspendedUntil(_ rateLimit: RateLimit?) -> Date? {
        guard let rateLimit, rateLimit.limit > 0,
            Double(rateLimit.remaining) / Double(rateLimit.limit) < 0.2
        else { return nil }
        return rateLimit.resetAt
    }
}
