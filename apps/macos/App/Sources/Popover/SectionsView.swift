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

    var body: some View {
        let sections = watch.sections(filter: model.filter)
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            if watch.config.selection.mode == .only, watch.config.selection.includedRepositories.isEmpty,
                watch.config.selection.includedOwners.isEmpty
            {
                EmptyLine(text: String(localized: "No repositories selected.", comment: "Empty state in only mode"))
                Button(
                    String(localized: "Choose Repositories…", comment: "Empty state button"),
                    action: actions.openSettings
                )
                .padding(.horizontal, 16)
            }
            switch model.tab {
            case .reviewRequested:
                let groups = sections.reviewRequested(model.triage)
                if groups.isEmpty { EmptyLine(text: emptyText(.reviewRequested)) }
                ForEach(groups) { group in
                    Section {
                        rows(group.items, .reviewRequested)
                    } header: {
                        RepositoryHeader(repository: group.repository, count: group.items.count)
                    }
                }
                notShown(.reviewRequested)
            case .mine:
                if sections.mine.isEmpty { EmptyLine(text: emptyText(.mine)) }
                if watch.config.mineLayout == .board {
                    MineBoard(groups: sections.mineGroups, now: now, actions: actions.row, focusedID: model.focusedID)
                } else {
                    ForEach(sections.mineGroups) { group in
                        let collapsed = group.kind == .draft && !model.draftsExpanded
                        Section {
                            if !collapsed { rows(group.items, .mine) }
                        } header: {
                            MineHeader(
                                kind: group.kind, count: group.items.count,
                                collapsed: group.kind == .draft ? collapsed : nil
                            ) {
                                model.draftsExpanded.toggle()
                            }
                        }
                    }
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
            if !model.filter.isEmpty, model.tab != .ignored {
                Button(String(localized: "Clear Filters", comment: "Filter button")) { model.filter = PopoverFilter() }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
        }
    }

    /// Rows with a hairline between each.
    private func rows(_ items: [WatchedPullRequest], _ placement: RowView.Placement) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            RowView(
                item: item, placement: placement, now: now, actions: actions.row, isFocused: model.focusedID == item.id)
            if index < items.count - 1 {
                Divider().padding(.leading, 29)
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
struct RepositoryHeader: View {
    let repository: String
    let count: Int

    var body: some View {
        let parts = repository.split(separator: "/", maxSplits: 1).map(String.init)
        let name = parts.last ?? repository
        HStack(spacing: 8) {
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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
