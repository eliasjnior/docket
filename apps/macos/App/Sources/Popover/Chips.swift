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

/// The time since the last human activity (`docs/05-design.md` §6.1), beside the age. Left out when it
/// reads the same as the age beside it, which is a pull request nobody touched since.
struct ActivityLabel: View {
    let elapsed: TimeInterval
    let besideAge: TimeInterval

    var body: some View {
        if Age.short(elapsed) != Age.short(besideAge) {
            HStack(spacing: 2) {
                Image(systemName: "clock.arrow.circlepath").font(.caption)
                Text(verbatim: Age.short(elapsed))
            }
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(Color.textSecondary)
            .fixedSize()
            .accessibilityHidden(true)
        }
    }
}

/// `+120 −30`, with `L` or `XL` before it for a pull request past one sitting (`docs/05-design.md` §6.1).
struct SizeLabel: View {
    let additions: Int?
    let deletions: Int?
    let files: Int?

    init(pullRequest: PullRequest) {
        additions = pullRequest.additions
        deletions = pullRequest.deletions
        files = pullRequest.changedFiles
    }

    /// A whole stack's lines and files.
    init(additions: Int?, deletions: Int?, files: Int?) {
        self.additions = additions
        self.deletions = deletions
        self.files = files
    }

    var body: some View {
        if let additions, let deletions {
            let size = PullRequestSize.of(lines: additions + deletions)
            HStack(spacing: 3) {
                if size.isLarge {
                    Text(verbatim: size == .extraLarge ? "XL" : "L")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.statusAttention)
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(Color.statusAttention.opacity(0.16)))
                }
                Text(verbatim: "+\(additions)").foregroundStyle(Color.statusReady)
                Text(verbatim: "−\(deletions)").foregroundStyle(Color.statusBlocking)
            }
            .font(.subheadline.monospacedDigit())
            .fixedSize()
            .help(tooltip(additions: additions, deletions: deletions))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: tooltip(additions: additions, deletions: deletions)))
        }
    }

    private func tooltip(additions: Int, deletions: Int) -> String {
        let files = files ?? 0
        return String(
            localized: "\(additions) lines added and \(deletions) deleted in \(files) files",
            comment: "Tooltip of a pull request's size")
    }
}

/// The repository's identity square and its name, for rows not grouped under a repository header
/// (`docs/05-design.md` §6.1). The owner is in the tooltip.
struct RepositoryTag: View {
    let repository: String

    var body: some View {
        let name = repository.split(separator: "/").last.map(String.init) ?? repository
        HStack(spacing: 4) {
            Text(verbatim: String(name.prefix(1)).uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 13, height: 13)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.identity(for: repository)))
            Text(verbatim: name).lineLimit(1).truncationMode(.tail)
        }
        .font(.subheadline)
        .foregroundStyle(Color.textSecondary)
        .help(repository)
        .accessibilityHidden(true)
    }
}

/// `2/3`: where a pull request sits in its stack, bottom first (`docs/05-design.md` §6.1).
struct StackBadge: View {
    let position: StackPosition

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "square.stack.3d.up.fill")
            Text(verbatim: "\(position.index)/\(position.count)").monospacedDigit()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.accent)
        .fixedSize()
        .help(
            String(
                localized: "\(position.index) of \(position.count) in a stack, from the bottom",
                comment: "Tooltip of the stack badge")
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("\(position.index) of \(position.count) in a stack", comment: "VoiceOver: stack position"))
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
