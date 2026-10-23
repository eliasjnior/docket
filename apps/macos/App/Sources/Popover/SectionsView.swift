import DocketActivity
import DocketCore
import DocketStores
import SwiftUI

/// The selected tab's rows (`docs/05-design.md` §5.3). Group headers stay pinned while scrolling.
struct SectionsView: View {
    let watch: WatchStore
    @Bindable var model: PopoverModel
    let actions: PopoverActions
    let now: Date
    /// The section to show; `nil` follows the selected tab. Columns pass theirs.
    var section: PopoverModel.Section?

    private var tab: PopoverModel.Section { section ?? model.tab }
    private var isBoard: Bool { watch.config.mineLayout == .board }

    var body: some View {
        let sections = watch.sections(filter: model.filter)
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            if watch.config.selection.mode == .only, watch.config.selection.includedRepositories.isEmpty,
                watch.config.selection.includedOwners.isEmpty
            {
                EmptyLine(text: String(localized: "No repositories selected.", comment: "Empty state in only mode"))
                Button(
                    String(localized: "Choose Repositories", comment: "Empty state button"),
                    action: actions.openSettings
                )
                .padding(.horizontal, 16)
            }
            switch tab {
            case .reviewRequested:
                let groups = sections.reviewRequested(model.triage)
                if groups.isEmpty { EmptyLine(text: emptyText(.reviewRequested)) }
                ForEach(groups) { group in
                    let collapsed = model.collapsedRepositories.contains(group.repository)
                    Section {
                        if !collapsed { rows(group.items, .reviewRequested) }
                    } header: {
                        RepositoryHeader(repository: group.repository, count: group.items.count, collapsed: collapsed) {
                            withMotion { model.toggle(repository: group.repository) }
                        }
                    }
                }
                notShown(.reviewRequested)
            case .mine:
                if sections.mine.isEmpty { EmptyLine(text: emptyText(.mine)) }
                if isBoard {
                    MineBoard(
                        groups: sections.mineListGroups, model: model, now: now,
                        staleAfterDays: watch.config.triage.staleAfterDays, actions: actions.row)
                } else {
                    // Stacks between Blocked and Draft: each is a unit of its own, whatever its rows' statuses.
                    // A stack is a block among its group's rows (`Sections.kind(of:)`), so it folds with it.
                    ForEach(sections.mineListGroups) { mineGroup($0) }
                }
                notShown(.authored)
            case .involved:
                if sections.involved.isEmpty { EmptyLine(text: emptyText(.involved)) }
                rows(sections.involved, .involved)
            case .ignored:
                if sections.ignored.isEmpty {
                    EmptyLine(text: String(localized: "Nothing is ignored.", comment: "Empty state"))
                }
                rows(sections.ignored, .ignored)
            }
            if !model.filter.isEmpty, tab != .ignored {
                Button(String(localized: "Clear Filters", comment: "Filter button")) { model.filter = PopoverFilter() }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
        }
    }

    private func mineGroup(_ group: Sections.MineGroup) -> some View {
        let collapsed = model.collapsedMineGroups.contains(group.kind)
        return Section {
            if !collapsed { rows(group.items, .mine) }
        } header: {
            MineHeader(kind: group.kind, count: group.items.count, collapsed: collapsed) {
                withMotion { model.toggle(group.kind) }
            }
        }
    }

    /// Each row in a box of its own; a stack's rows, already together, share one block.
    private func rows(_ items: [WatchedPullRequest], _ placement: RowView.Placement) -> some View {
        let segments = RowSegment.split(items)
        return Group {
            if !segments.isEmpty { edge }
            ForEach(segments) { segment in
                switch segment {
                case .row(let item):
                    row(item, placement).modifier(RowBox())
                case .stack(let stack):
                    stackBlock(stack, placement)
                }
            }
            if !segments.isEmpty { edge }
        }
    }

    /// The other half of a box's inset at either end of a list, so the first and last box sit as far from the
    /// headers as from the sides.
    private var edge: some View {
        Color.clear.frame(height: RowBox.inset / 2)
    }

    private func row(_ item: WatchedPullRequest, _ placement: RowView.Placement) -> some View {
        RowView(item: item, placement: placement, now: now, actions: actions.row, isFocused: model.focusedID == item.id)
    }

    private func stackBlock(_ stack: Stack, _ placement: RowView.Placement) -> some View {
        StackBlock(
            stack: stack, now: now, staleAfterDays: watch.config.triage.staleAfterDays,
            collapsed: model.collapsedStacks.contains(stack.id)
        ) {
            withMotion { model.toggle(stack: stack.id) }
        } rows: {
            ForEach(Array(stack.items.enumerated()), id: \.element.id) { index, item in
                row(item, placement)
                if index < stack.items.count - 1 { Divider() }
            }
        }
    }

    private func emptyText(_ section: PopoverModel.Section) -> String {
        if !model.filter.isEmpty {
            return String(localized: "Nothing matches these filters.", comment: "Empty state with filters")
        }
        switch section {
        case .reviewRequested:
            return switch model.triage {
            case .humans: String(localized: "No reviews waiting on you.", comment: "Empty state")
            case .bots: String(localized: "No review requests from bots.", comment: "Empty state")
            case .drafts: String(localized: "No drafts waiting on you.", comment: "Empty state")
            case .stale: String(localized: "Nothing stale.", comment: "Empty state")
            }
        case .mine:
            return String(
                localized: "No open pull requests of yours in the watched repositories.", comment: "Empty state")
        case .involved, .ignored:
            return String(
                localized: "Nothing you commented on or reviewed in the last 30 days.", comment: "Empty state")
        }
    }

    @ViewBuilder
    private func notShown(_ role: Role) -> some View {
        let hidden = watch.notShown(role)
        if hidden > 0 {
            Text("+\(hidden) not shown", comment: "More results than the search returned")
                .font(.subheadline).foregroundStyle(Color.textTertiary).padding(.horizontal, 16).padding(.vertical, 6)
        }
    }
}

/// A repository group: a raised band with the repository's colour, owner dimmed, name strong, count right.
/// Clicking it folds the group.
struct RepositoryHeader: View {
    let repository: String
    let count: Int
    var collapsed = false
    var toggle: () -> Void = {}

    var body: some View {
        Button(action: toggle) { label }
            .buttonStyle(.plain)
            .accessibilityValue(DisclosureChevron.accessibilityValue(collapsed: collapsed))
    }

    private var label: some View {
        let parts = repository.split(separator: "/", maxSplits: 1).map(String.init)
        let name = parts.last ?? repository
        return HStack(spacing: 8) {
            DisclosureChevron(collapsed: collapsed)
            Text(verbatim: String(name.prefix(1)).uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.identity(for: repository)))
            if parts.count == 2 {
                Text(verbatim: "\(parts[0]) /").foregroundStyle(Color.textSecondary)
            }
            Text(verbatim: name).fontWeight(.semibold).foregroundStyle(Color.textPrimary)
            Spacer(minLength: 4)
            CountBadge(count: count)
        }
        .font(.subheadline)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.regularMaterial)
        .background(Color.fillRaised)
        .overlay(alignment: .bottom) { Hairline() }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The arrow on a group header: right when folded, down when open.
struct DisclosureChevron: View {
    let collapsed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.textSecondary)
            .rotationEffect(.degrees(collapsed ? 0 : 90))
            .animation(reduceMotion ? nil : .default, value: collapsed)
            .frame(width: 10)
            .accessibilityHidden(true)
    }

    static func accessibilityValue(collapsed: Bool) -> String {
        collapsed
            ? String(localized: "Collapsed", comment: "Group header state")
            : String(localized: "Expanded", comment: "Group header state")
    }
}

/// A horizontal separator; a `Divider` in an overlay would be vertical.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
    }
}

struct EmptyLine: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.subheadline)
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
    }
}
