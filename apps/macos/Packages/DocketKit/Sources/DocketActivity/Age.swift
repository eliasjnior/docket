import Foundation

/// How long something has been open or waiting (`docs/02-activity-detection.md` §3.4).
public enum Age {
    public enum Style: Hashable, Sendable {
        case normal
        /// Over 72 hours.
        case ageing
        /// Over 7 days.
        case stale
    }

    /// `now`, `Nm`, `Nh`, `Nd` or `Nw`, always rounded down.
    public static func short(_ elapsed: TimeInterval) -> String {
        let seconds = max(0, elapsed)
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86400: return "\(Int(seconds / 3600))h"
        case ..<(14 * 86400): return "\(Int(seconds / 86400))d"
        default: return "\(Int(seconds / (7 * 86400)))w"
        }
    }

    public static func style(_ elapsed: TimeInterval) -> Style {
        if elapsed > 7 * 86400 { return .stale }
        if elapsed > 72 * 3600 { return .ageing }
        return .normal
    }
}
