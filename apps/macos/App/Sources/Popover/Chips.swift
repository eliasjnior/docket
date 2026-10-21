import DocketActivity
import DocketCore
import SwiftUI

/// The status chip of `docs/05-design.md` §6.3: symbol in its colour, word in the primary text colour.
struct StatusChip: View {
    let status: Status
    /// No fill and a secondary word, in *Review requested*.
    var secondary = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: status.symbol).foregroundStyle(status.color)
            Text(secondary ? status.shortLabel : status.label)
                .foregroundStyle(secondary ? Color.textSecondary : Color.textPrimary)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, secondary ? 0 : 4)
        .padding(.vertical, 2)
        .background {
            if !secondary { Capsule().fill(status.color.opacity(0.12)) }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

struct DraftChip: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "pencil")
            Text("Draft", comment: "The draft modifier beside the status chip")
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Color.statusNeutral)
        .fixedSize()
    }
}

struct TagChip: View {
    let tag: String
    var action: (() -> Void)?

    var body: some View {
        Text(verbatim: tag)
            .font(.subheadline)
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.fillTag))
            .fixedSize()
            .onTapGesture { action?() }
    }
}

/// An age or waited time with its ageing and stale styles (`docs/05-design.md` §6.2).
struct AgeLabel: View {
    let elapsed: TimeInterval
    var prefix: String?

    var body: some View {
        let style = Age.style(elapsed)
        HStack(spacing: 3) {
            if let prefix { Text(verbatim: prefix) }
            if style != .normal {
                Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(Color.statusAttention)
            }
            Text(verbatim: Age.short(elapsed)).fontWeight(style == .stale ? .semibold : .regular)
        }
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(Color.textSecondary)
        .fixedSize()
    }
}

struct ReviewerLabel: View {
    let entry: ReviewerEntry

    var body: some View {
        HStack(spacing: 2) {
            if let symbol { Image(systemName: symbol) }
            Text(verbatim: entry.handle)
            if entry.reRequested { Text("re-requested", comment: "After a reviewer asked to review again") }
        }
        .font(.subheadline)
        .foregroundStyle(Color.textSecondary)
        .fixedSize()
    }

    private var symbol: String? {
        switch entry.state {
        case .pending: "circle.dashed"
        case .approved: "checkmark"
        case .changesRequested: "arrow.uturn.backward"
        case .commented: "text.bubble"
        }
    }
}
