import AppKit
import DocketCore
import SwiftUI

/// The colour tokens of `docs/05-design.md` §10.2. No hex value appears in the code.
extension Color {
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    static let accentMarked = Color(nsColor: .controlAccentColor)
    static let statusBlocking = Color(nsColor: .systemRed)
    static let statusAttention = Color(nsColor: .systemOrange)
    static let statusReady = Color(nsColor: .systemGreen)
    static let statusNeutral = Color(nsColor: .secondaryLabelColor)
    static let statusRunning = Color(nsColor: .systemYellow)
    static let statusWaiting = Color(nsColor: .systemBlue)
    static let fillTag = Color(nsColor: .quaternarySystemFill)
    /// The selected tab, unseen rows and the count circles (`docs/05-design.md` §10.2).
    static let accent = Color(nsColor: .controlAccentColor)
    static let fillRaised = Color(nsColor: .quaternaryLabelColor).opacity(0.5)
    static let fillBadge = Color(nsColor: .tertiaryLabelColor).opacity(0.6)

    /// One colour per name, stable across launches. Red, orange and green are left to status.
    static func identity(for name: String) -> Color {
        let palette: [NSColor] = [
            .systemBlue, .systemPurple, .systemPink, .systemTeal, .systemIndigo, .systemCyan, .systemBrown, .systemMint,
        ]
        // FNV-1a: `hashValue` changes between launches.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in name.lowercased().utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return Color(nsColor: palette[Int(hash % UInt64(palette.count))])
    }

    /// A GitHub label colour (`rrggbb`), or `nil` when it does not parse.
    init?(hex: String) {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}

extension Status {
    var symbol: String {
        switch self {
        case .conflict: "exclamationmark.triangle.fill"
        case .checksFailing: "xmark.circle.fill"
        case .changesRequested: "arrow.uturn.backward.circle.fill"
        case .checksRunning: "circle.dotted"
        case .readyToMerge: "checkmark.circle.fill"
        case .waitingForReview: "eye"
        case .noReviewers: "person.crop.circle.badge.questionmark"
        }
    }

    var label: String {
        switch self {
        case .conflict: String(localized: "Conflict", comment: "Status chip: the pull request has a merge conflict")
        case .checksFailing: String(localized: "Checks failing", comment: "Status chip")
        case .changesRequested: String(localized: "Changes requested", comment: "Status chip")
        case .checksRunning: String(localized: "Checks running", comment: "Status chip")
        case .readyToMerge: String(localized: "Ready to merge", comment: "Status chip")
        case .waitingForReview: String(localized: "Waiting for review", comment: "Status chip")
        case .noReviewers: String(localized: "No reviewers", comment: "Status chip")
        }
    }

    /// `Ready to merge` shortens to `Ready` in *Review requested* (`docs/05-design.md` §6.3).
    var shortLabel: String {
        self == .readyToMerge ? String(localized: "Ready", comment: "Secondary status chip in Review requested") : label
    }

    var color: Color {
        switch self {
        case .conflict, .checksFailing: .statusBlocking
        case .changesRequested: .statusAttention
        case .readyToMerge: .statusReady
        case .checksRunning: .statusRunning
        case .waitingForReview: .statusWaiting
        case .noReviewers: .statusNeutral
        }
    }

    /// Yellow text is unreadable on a light popover; the symbol keeps the colour.
    var textColor: Color { self == .checksRunning ? .textPrimary : color }
}
