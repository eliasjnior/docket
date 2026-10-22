import DocketActivity
import DocketCore
import DocketStores
import SwiftUI

/// Under the tabs: the sub-tabs of *Review requested* and the actions menu, then the filter chips
/// (`docs/05-design.md` §5.2).
struct FilterBar: View {
    let watch: WatchStore
    @Bindable var model: PopoverModel
    let actions: PopoverActions

    var body: some View {
        let sections = watch.sections(filter: model.filter)
        VStack(alignment: .leading, spacing: 8) {
            if model.tab == .reviewRequested {
                HStack(spacing: 6) {
                    ForEach(Triage.allCases, id: \.self) { triage in
                        subTab(triage, count: sections.triageCounts[triage] ?? 0)
                    }
                    Spacer(minLength: 0)
                    ActionsMenu(model: model, sections: sections, layout: watch.config.mineLayout, actions: actions)
                }
            }
            HStack(spacing: 6) {
                FilterChips(watch: watch, model: model)
                Spacer(minLength: 0)
                if model.tab != .reviewRequested {
                    ActionsMenu(model: model, sections: sections, layout: watch.config.mineLayout, actions: actions)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private func subTab(_ triage: Triage, count: Int) -> some View {
        let selected = model.triage == triage
        return Button {
            model.triage = triage
            model.focusedID = nil
        } label: {
            HStack(spacing: 8) {
                Text(verbatim: triage.title)
                CountBadge(count: count, selected: selected)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(selected ? Color.white : Color.textPrimary)
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .frame(height: 28)
            .background(Capsule().fill(selected ? Color.accent : Color.fillTag))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(Text(verbatim: "\(triage.title), \(count)"))
    }
}

extension Triage {
    var title: String {
        switch self {
        case .humans: String(localized: "Humans", comment: "Review requested sub-tab")
        case .bots: String(localized: "Bots", comment: "Review requested sub-tab")
        case .drafts: String(localized: "Drafts", comment: "Review requested sub-tab")
        case .stale: String(localized: "Stale", comment: "Review requested sub-tab")
        }
    }
}

/// `•••`: actions on the visible list.
struct ActionsMenu: View {
    let model: PopoverModel
    let sections: Sections
    let layout: Config.MineLayout
    let actions: PopoverActions

    var body: some View {
        Menu {
            Button(String(localized: "Mark All as Seen", comment: "Actions menu")) {
                actions.row.markSeen(PopoverView.visibleItems(sections, model: model, layout: layout).map(\.id))
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 28, height: 28)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.fillTag))
        .help(String(localized: "Actions", comment: "Actions menu button"))
        .accessibilityLabel(Text("Actions", comment: "Actions menu button"))
    }
}

/// One chip per active filter, then `+ Filter`, a menu per dimension of the values in the current tab.
struct FilterChips: View {
    let watch: WatchStore
    @Bindable var model: PopoverModel

    var body: some View {
        let items = tabItems
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips(summarized: false) }
            HStack(spacing: 6) { chips(summarized: true) }
        }
        Menu {
            ForEach(PopoverFilter.Dimension.allCases, id: \.self) { dimension in
                let values = Self.values(dimension, in: items)
                if !values.isEmpty {
                    Menu(dimension.title) {
                        ForEach(values, id: \.value) { entry in
                            Toggle(
                                "\(entry.label) (\(entry.count))",
                                isOn: Binding(
                                    get: { model.filter.contains(entry.value, in: dimension) },
                                    set: { _ in model.filter.toggle(entry.value, in: dimension) }))
                        }
                    }
                }
            }
        } label: {
            Text("+ Filter", comment: "Add filter button")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .controlSize(.small)
        .fixedSize()
        // A borderless menu drops its label's styling, so the chip is drawn around the menu itself.
        .font(.subheadline)
        .foregroundStyle(Color.textSecondary)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .overlay(
            RoundedRectangle(cornerRadius: 7).strokeBorder(
                Color.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3])))
    }

    @ViewBuilder
    private func chips(summarized: Bool) -> some View {
        ForEach(PopoverFilter.Dimension.allCases, id: \.self) { dimension in
            if !model.filter.isEmpty(dimension) {
                let selected = Self.selected(dimension, in: model.filter)
                HStack(spacing: 6) {
                    Text(verbatim: dimension.title + ": ").foregroundStyle(Color.textSecondary)
                        + Text(
                            verbatim: summarized && selected.count > 1
                                ? "\(selected.count)" : selected.joined(separator: ", ")
                        )
                        .fontWeight(.semibold)
                    Button {
                        model.filter.clear(dimension)
                    } label: {
                        Image(systemName: "xmark").font(.caption2.weight(.bold))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Clear filter", comment: "Filter chip"))
                }
                .font(.subheadline)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.fillTag))
                .fixedSize()
            }
        }
    }

    /// The rows of the current tab with no filter, so a value can be added even if it shows nothing now.
    private var tabItems: [WatchedPullRequest] {
        let all = watch.sections()
        return switch model.tab {
        case .reviewRequested: all.reviewRequested.flatMap(\.items)
        case .mine: all.mine
        case .involved: all.involved
        case .ignored: all.ignored
        }
    }

    struct Value {
        var value: String
        var label: String
        var count: Int
    }

    static func values(_ dimension: PopoverFilter.Dimension, in items: [WatchedPullRequest]) -> [Value] {
        let names: [(String, String)] = items.flatMap { item -> [(String, String)] in
            let pullRequest = item.pullRequest
            return switch dimension {
            case .organization: [(pullRequest.owner, pullRequest.owner)]
            case .repository: [(pullRequest.repository, pullRequest.repository)]
            case .label: pullRequest.labels.map { ($0.name, $0.name) }
            case .status: [(item.status.rawValue, item.status.label)]
            }
        }
        let grouped = Dictionary(grouping: names) { $0.0.lowercased() }
        return grouped.values.compactMap { group in
            group.first.map { Value(value: $0.0, label: $0.1, count: group.count) }
        }
        .sorted { ($0.count, $1.label.lowercased()) > ($1.count, $0.label.lowercased()) }
    }

    static func selected(_ dimension: PopoverFilter.Dimension, in filter: PopoverFilter) -> [String] {
        switch dimension {
        case .organization: filter.organizations.sorted()
        case .repository: filter.repositories.sorted()
        case .label: filter.labels.sorted()
        case .status: filter.statuses.sorted().map(\.label)
        }
    }
}

extension PopoverFilter.Dimension {
    var title: String {
        switch self {
        case .organization: String(localized: "Org", comment: "Filter dimension")
        case .repository: String(localized: "Repo", comment: "Filter dimension")
        case .label: String(localized: "Label", comment: "Filter dimension")
        case .status: String(localized: "Status", comment: "Filter dimension")
        }
    }
}
