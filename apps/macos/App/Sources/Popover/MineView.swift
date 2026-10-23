import DocketActivity
import DocketCore
import SwiftUI

/// *Mine* in Ready, Blocked and Draft (`docs/05-design.md` §5.3): stacked sections or a board.
extension MineKind {
    var title: String {
        switch self {
        case .ready: String(localized: "Ready", comment: "Mine group")
        case .blocked: String(localized: "Blocked", comment: "Mine group")
        case .draft: String(localized: "Draft", comment: "Mine group")
        }
    }

    var color: Color {
        switch self {
        case .ready: .statusReady
        case .blocked: .statusBlocking
        case .draft: .statusNeutral
        }
    }
}

extension WatchedPullRequest {
    /// Why a blocked pull request is blocked, in words.
    var blockedReason: String? {
        guard MineKind.of(self) == .blocked else { return nil }
        switch status {
        case .conflict: return String(localized: "Conflict with the base branch", comment: "Blocked reason")
        case .checksFailing: return String(localized: "Checks failing", comment: "Blocked reason")
        case .changesRequested:
            let who = reviewers.filter { $0.state == .changesRequested }.map(\.handle)
            return who.isEmpty
                ? String(localized: "Changes requested", comment: "Blocked reason")
                : String(
                    localized: "Changes requested by \(who.joined(separator: ", "))", comment: "Blocked reason")
        default: return nil
        }
    }
}

struct MineHeader: View {
    let kind: MineKind
    let count: Int
    var collapsed = false
    var toggle: () -> Void = {}

    var body: some View {
        Button(action: toggle) { label }
            .buttonStyle(.plain)
            .accessibilityValue(DisclosureChevron.accessibilityValue(collapsed: collapsed))
    }

    private var label: some View {
        HStack(spacing: 8) {
            DisclosureChevron(collapsed: collapsed)
            Circle().fill(kind.color).frame(width: 8, height: 8)
            Text(verbatim: kind.title).fontWeight(.semibold)
            Spacer(minLength: 4)
            CountBadge(count: count)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.regularMaterial)
        .background(Color.fillRaised)
        .overlay(alignment: .bottom) { Hairline() }
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isHeader)
    }
}

/// Three columns side by side, like a board. A card's column follows from its state; nothing is dragged.
struct MineBoard: View {
    let groups: [Sections.MineGroup]
    let now: Date
    let actions: RowActions
    var focusedID: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(MineKind.allCases, id: \.self) { kind in
                let items = groups.first { $0.kind == kind }?.items ?? []
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle().fill(kind.color).frame(width: 8, height: 8)
                        Text(verbatim: kind.title).fontWeight(.semibold)
                        Spacer(minLength: 4)
                        CountBadge(count: items.count)
                    }
                    .font(.subheadline)
                    .padding(.bottom, 2)
                    ForEach(items) { BoardCard(item: $0, now: now, actions: actions, isFocused: $0.id == focusedID) }
                    if items.isEmpty {
                        Text("Nothing here", comment: "Empty board column").font(.subheadline)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.fillTag))
            }
        }
        .padding(12)
    }
}

struct BoardCard: View {
    let item: WatchedPullRequest
    let now: Date
    let actions: RowActions
    var isFocused = false
    @State private var isHovered = false

    var body: some View {
        let pullRequest = item.pullRequest
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5).fill(item.status.color).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: pullRequest.title)
                    .font(.subheadline.weight(item.isUnseen ? .semibold : .regular))
                    .foregroundStyle(item.isUnseen ? Color.textPrimary : Color.textSecondary)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text(verbatim: "\(pullRequest.repository) #\(pullRequest.number)")
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 2)
                    AgeLabel(elapsed: now.timeIntervalSince(pullRequest.createdAt))
                }
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                if let reason = item.blockedReason {
                    Text(verbatim: reason).font(.caption.weight(.medium)).foregroundStyle(item.status.color)
                        .lineLimit(2)
                } else {
                    StatusChip(status: item.status, short: true)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The status rail is a shape and takes every point offered, so a short column would stretch its card.
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 7).fill(
                item.isUnseen ? Color.accent.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accent, lineWidth: 2)
            } else if isHovered {
                RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accent.opacity(0.6), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { actions.open(item) }
        .contextMenu { RowMenu(item: item, actions: actions) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RowAccessibility.label(for: item, placement: .mine, now: now))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { actions.open(item) }
    }
}
