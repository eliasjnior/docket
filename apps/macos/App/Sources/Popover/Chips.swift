import AppKit
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
        let color = Self.color(for: tag)
        Text(verbatim: tag)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .fixedSize()
            .onTapGesture { action?() }
    }

    /// One colour per tag name, stable across launches. Red, orange and green are left to status.
    static func color(for tag: String) -> Color {
        let palette: [NSColor] = [
            .systemBlue, .systemPurple, .systemPink, .systemTeal, .systemIndigo, .systemCyan, .systemBrown, .systemMint,
        ]
        // FNV-1a: `hashValue` changes between launches.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in tag.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return Color(nsColor: palette[Int(hash % UInt64(palette.count))])
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
