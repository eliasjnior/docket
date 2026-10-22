import AppKit
import DocketActivity
import DocketCore
import SwiftUI

/// The status pill of `docs/05-design.md` §6.3: a filled capsule, the symbol and word in the status colour.
struct StatusChip: View {
    let status: Status
    /// `Ready to merge` shortens to `Ready` in *Review requested*.
    var short = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.color)
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: status == .checksRunning)
            Text(short ? status.shortLabel : status.label).foregroundStyle(status.textColor)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(status.color.opacity(0.16)))
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

/// A GitHub label in its own colour, outlined so a pale or dark colour still reads on the popover.
struct LabelChip: View {
    let label: DocketCore.Label
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let base = Color(hex: label.color) ?? .textSecondary
        let text = colorScheme == .dark ? base.mix(with: .white, by: 0.35) : base.mix(with: .black, by: 0.35)
        Text(verbatim: label.name)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(text)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(Capsule().fill(base.opacity(0.14)))
            .overlay(Capsule().strokeBorder(base.opacity(0.55), lineWidth: 1))
            .fixedSize()
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
