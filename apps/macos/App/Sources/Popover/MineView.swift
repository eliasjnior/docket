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
        guard role == .authored, MineKind.blockingStatuses.contains(status) else { return nil }
        switch status {
        case .checksWaiting: return waitingReason
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

    /// `e2e is waiting: Comment /e2e to run` for one check; `e2e and deploy are waiting` for several, whose
    /// details are in `waitingDetails`.
    var waitingReason: String? {
        guard let check = waitingChecks.first else { return nil }
        guard waitingChecks.count == 1 else {
            let names = waitingChecks.map(\.name).formatted(.list(type: .and))
            return String(localized: "\(names) are waiting", comment: "Checks waiting reason, several checks")
        }
        return check.waitingLine
    }

    /// Every waiting check on a line of its own, for the status chip's tooltip.
    var waitingDetails: String? {
        waitingChecks.isEmpty ? nil : waitingChecks.map(\.waitingLine).joined(separator: "\n")
    }
}

extension WaitingCheck {
    var waitingLine: String {
        if isApproval {
            return String(localized: "\(name) is waiting for an approval", comment: "Checks waiting reason")
        }
        guard let detail, !detail.isEmpty else {
            return String(localized: "\(name) is waiting", comment: "Checks waiting reason")
        }
        return String(localized: "\(name) is waiting: \(detail)", comment: "Checks waiting reason")
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
    let model: PopoverModel
    let now: Date
    var staleAfterDays = 7
    let actions: RowActions

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
                    ForEach(Sections.byRepository(items)) { group in
                        let collapsed = model.isCollapsed(kind, group.repository)
                        BoardRepositoryHeader(
                            repository: group.repository, count: group.items.count, collapsed: collapsed
                        ) {
                            withMotion { model.toggle(kind, repository: group.repository) }
                        }
                        if !collapsed {
                            // A stack stays whole, in one block, as in the list.
                            ForEach(RowSegment.split(group.items)) { segment in
                                switch segment {
                                case .row(let item): card(item)
                                case .stack(let stack): stackBlock(stack)
                                }
                            }
                        }
                    }
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

    private func card(_ item: WatchedPullRequest) -> some View {
        BoardCard(item: item, now: now, actions: actions, isFocused: item.id == model.focusedID)
    }

    /// The board's stack block: the list's border and tint, a one-line header, then the cards bottom to top.
    private func stackBlock(_ stack: Stack) -> some View {
        let collapsed = model.collapsedStacks.contains(stack.id)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withMotion { model.toggle(stack: stack.id) }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        DisclosureChevron(collapsed: collapsed)
                        Image(systemName: "square.stack.3d.up.fill").foregroundStyle(Color.accent)
                        Text("Stack of \(stack.items.count)", comment: "Board stack header").fontWeight(.semibold)
                        Spacer(minLength: 2)
                        ActivityLabel(
                            elapsed: now.timeIntervalSince(stack.lastActivity),
                            besideAge: now.timeIntervalSince(stack.createdAt))
                        AgeLabel(elapsed: now.timeIntervalSince(stack.createdAt))
                    }
                    StackSummary(stack: stack, now: now, staleAfterDays: staleAfterDays, stacked: true)
                    if collapsed { StackNumbers(stack: stack) }
                }
                .font(.caption)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(DisclosureChevron.accessibilityValue(collapsed: collapsed))
            if !collapsed { ForEach(stack.items) { card($0) } }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.accent.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.accent.opacity(0.5)))
    }
}

/// A folded stack's pull requests, bottom to top, `#475 → #476`, each number in its status's colour.
struct StackNumbers: View {
    let stack: Stack

    var body: some View {
        stack.items.enumerated().reduce(Text(verbatim: "")) { line, entry in
            let (index, item) = entry
            let number = Text(verbatim: "#\(item.pullRequest.number)").foregroundColor(item.status.color)
            return index == 0 ? number : line + Text(verbatim: " → ").foregroundColor(.secondary) + number
        }
        .font(.subheadline.monospacedDigit().weight(.medium))
        .lineLimit(2)
        .help(stack.items.map { "#\($0.pullRequest.number) \($0.pullRequest.title)" }.joined(separator: "\n"))
    }
}

/// What a row would say, for a stack as a whole: the status that needs you first, `Stale`, the summed size and
/// the files. Items leave from the end when the line is narrow, as on a board column.
struct StackSummary: View {
    let stack: Stack
    let now: Date
    let staleAfterDays: Int
    /// On a board column: the status on one line, the size and files on the next.
    var stacked = false

    var body: some View {
        if stacked {
            VStack(alignment: .leading, spacing: 4) {
                DropLayout(spacing: 6) { status }
                DropLayout(spacing: 6) { size }
            }
        } else {
            DropLayout(spacing: 6) {
                status
                size
            }
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private var status: some View {
        if let status = stack.status { StatusChip(status: status, short: true) }
        if stack.isStale(now: now, staleAfterDays: staleAfterDays) {
            Text("Stale", comment: "Stack header: no human activity for the stale period")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.statusAttention)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.statusAttention.opacity(0.16)))
                .help(
                    String(
                        localized: "No human activity for \(staleAfterDays) days",
                        comment: "Tooltip of the stale chip on a stack"))
        }
    }

    @ViewBuilder
    private var size: some View {
        SizeLabel(additions: stack.additions, deletions: stack.deletions, files: stack.changedFiles)
            .layoutValue(key: DropRank.self, value: 1)
        if let files = stack.changedFiles {
            Text("\(files) files", comment: "Stack header: files changed across the stack")
                .font(.subheadline).foregroundStyle(Color.textSecondary)
                .layoutValue(key: DropRank.self, value: 2)
        }
    }
}

/// A stack's rows in a block of their own: an accent border and tint, and a header with the stack symbol, the
/// number of pull requests, the repository and the branch it merges into. The chevron folds the rows.
struct StackBlock<Rows: View>: View {
    let stack: Stack
    let now: Date
    let staleAfterDays: Int
    let collapsed: Bool
    let toggle: () -> Void
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggle) { header }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isHeader)
                .accessibilityValue(DisclosureChevron.accessibilityValue(collapsed: collapsed))
            if !collapsed {
                Rectangle().fill(Color.accent.opacity(0.35)).frame(height: 1)
                rows()
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accent.opacity(0.06)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accent.opacity(0.5), lineWidth: 1))
        .padding(.horizontal, RowBox.inset)
        .padding(.vertical, RowBox.inset / 2)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                DisclosureChevron(collapsed: collapsed)
                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(Color.accent)
                Text("Stack of \(stack.items.count) pull requests", comment: "Stack block header")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                RepositoryTag(repository: stack.repository).fixedSize()
                if let base = stack.base {
                    Text("on \(base)", comment: "Stack header: the branch the stack merges into")
                        .foregroundStyle(Color.textSecondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 4)
                ActivityLabel(
                    elapsed: now.timeIntervalSince(stack.lastActivity),
                    besideAge: now.timeIntervalSince(stack.createdAt))
                AgeLabel(elapsed: now.timeIntervalSince(stack.createdAt))
            }
            StackSummary(stack: stack, now: now, staleAfterDays: staleAfterDays)
                .padding(.leading, 18)
            if collapsed { StackNumbers(stack: stack).padding(.leading, 18) }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// A repository inside a board column: the tag, the count, and a chevron that folds its cards.
struct BoardRepositoryHeader: View {
    let repository: String
    let count: Int
    let collapsed: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                DisclosureChevron(collapsed: collapsed)
                RepositoryTag(repository: repository)
                Spacer(minLength: 4)
                if collapsed {
                    Text(verbatim: "\(count)").font(.caption.monospacedDigit()).foregroundStyle(Color.textSecondary)
                }
            }
            .font(.caption.weight(.semibold))
            .padding(.top, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(DisclosureChevron.accessibilityValue(collapsed: collapsed))
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
                // A narrow card gives up the last activity, then the size; the number never wraps.
                ViewThatFits(in: .horizontal) {
                    meta(size: true, activity: true)
                    meta(size: true, activity: false)
                    meta(size: false, activity: false)
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

    private func meta(size: Bool, activity: Bool) -> some View {
        let pullRequest = item.pullRequest
        return HStack(spacing: 4) {
            Text(verbatim: "#\(pullRequest.number)").monospacedDigit().fixedSize()
            if let position = item.stackPosition { StackBadge(position: position) }
            Spacer(minLength: 2)
            if size { SizeLabel(pullRequest: pullRequest) }
            if activity {
                ActivityLabel(
                    elapsed: now.timeIntervalSince(item.lastActivity),
                    besideAge: now.timeIntervalSince(pullRequest.createdAt))
            }
            AgeLabel(elapsed: now.timeIntervalSince(pullRequest.createdAt))
        }
    }
}
