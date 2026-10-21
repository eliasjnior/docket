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
    static let fillTag = Color(nsColor: .quaternarySystemFill)
}

extension Status {
    var symbol: String {
        switch self {
        case .conflict: "exclamationmark.triangle.fill"
        case .checksFailing: "xmark.circle.fill"
        case .changesRequested: "arrow.uturn.backward.circle.fill"
        case .checksRunning: "hourglass"
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
        case .checksRunning, .waitingForReview, .noReviewers: .statusNeutral
        }
    }
}
