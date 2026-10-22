import DocketActivity
import DocketCore
import DocketStores
import SwiftUI

/// The popover of `docs/05-design.md` §5: header, banners, tabs, filters, then the list or a full screen.
struct PopoverView: View {
    static let width: CGFloat = 420
    static let boardWidth: CGFloat = 640

    let watch: WatchStore
    @Bindable var model: PopoverModel
    let permission: NotificationPermission
    let actions: PopoverActions
    /// The list's real height: a lazy stack's ideal height is an estimate, which left empty space around it.
    @State private var listHeight: CGFloat = 0

    private var maxHeight: CGFloat {
        min(640, (NSScreen.main?.visibleFrame.height ?? 800) - 40)
    }

    private var isBoard: Bool { model.tab == .mine && watch.config.mineLayout == .board }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date.addingTimeInterval(watch.snapshot.state.lastPoll?.serverTimeOffset ?? 0)
            VStack(spacing: 0) {
                PopoverHeader(watch: watch, actions: actions)
                Banners(watch: watch, permission: permission, actions: actions, now: context.date)
                if let screen = FullScreen.for(watch: watch) {
                    Divider()
                    FullScreenView(screen: screen, actions: actions).padding(20)
                } else {
                    TabBar(watch: watch, model: model)
                    FilterBar(watch: watch, model: model, actions: actions)
                    Divider()
                    ScrollView {
                        SectionsView(watch: watch, model: model, actions: actions, now: now)
                            .padding(.bottom, 6)
                            .onGeometryChange(for: CGFloat.self) {
                                $0.size.height
                            } action: {
                                listHeight = $0
                            }
                    }
                    .frame(height: min(max(listHeight, 40), maxHeight - 150))
                }
            }
        }
        .frame(width: isBoard ? Self.boardWidth : Self.width)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.leftArrow) { switchTab(-1) }
        .onKeyPress(.rightArrow) { switchTab(1) }
        .onKeyPress(.return) {
            guard let item = focusedItem else { return .ignored }
            actions.row.open(item)
            return .handled
        }
        .onExitCommand {
            if !model.clearFilter() { actions.close() }
        }
        .background {
            Button("") { actions.refresh() }.keyboardShortcut("r").hidden()
            Button("") { actions.openSettings() }.keyboardShortcut(",").hidden()
        }
    }
}

extension PopoverView {
    /// The rows of the current tab and sub-tab, in display order.
    var visibleItems: [WatchedPullRequest] {
        Self.visibleItems(watch.sections(filter: model.filter), model: model, layout: watch.config.mineLayout)
    }

    /// What is on screen: a collapsed Draft group is not.
    static func visibleItems(_ sections: Sections, model: PopoverModel, layout: Config.MineLayout)
        -> [WatchedPullRequest]
    {
        switch model.tab {
        case .reviewRequested: sections.reviewRequested(model.triage).flatMap(\.items)
        case .mine:
            sections.mineGroups.filter { $0.kind != .draft || layout == .board || model.draftsExpanded }
                .flatMap(\.items)
        case .involved: sections.involved
        case .ignored: sections.ignored
        }
    }

    var focusedItem: WatchedPullRequest? {
        visibleItems.first { $0.id == model.focusedID }
    }

    func move(_ step: Int) -> KeyPress.Result {
        let items = visibleItems
        guard !items.isEmpty else { return .ignored }
        let index = items.firstIndex { $0.id == model.focusedID }.map { $0 + step } ?? (step > 0 ? 0 : items.count - 1)
        model.focusedID = items[min(max(index, 0), items.count - 1)].id
        return .handled
    }

    func switchTab(_ step: Int) -> KeyPress.Result {
        var tabs: [PopoverModel.Section] = [.reviewRequested, .mine, .involved]
        if !watch.sections(filter: model.filter).ignored.isEmpty { tabs.append(.ignored) }
        guard let index = tabs.firstIndex(of: model.tab) else { return .ignored }
        model.tab = tabs[(index + step + tabs.count) % tabs.count]
        model.focusedID = nil
        return .handled
    }
}

/// The logo, the name, refresh and settings. The refresh symbol spinning is the only progress signal.
struct PopoverHeader: View {
    let watch: WatchStore
    let actions: PopoverActions

    var body: some View {
        HStack(spacing: 8) {
            AppIconView(size: 22)
            Text(verbatim: "Docket").font(.headline)
            Spacer()
            Button(action: actions.refresh) {
                Image(systemName: "arrow.clockwise")
                    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: watch.isPolling)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Refresh", comment: "Refresh button"))
            .accessibilityLabel(
                watch.isPolling
                    ? Text("Refreshing", comment: "Refresh button while a poll runs")
                    : Text("Refresh", comment: "Refresh button"))
            Menu {
                Button(String(localized: "Settings…", comment: "Gear menu"), action: actions.openSettings)
                Button(String(localized: "Check for Updates…", comment: "Gear menu"), action: actions.checkForUpdates)
                Divider()
                Button(String(localized: "Quit Docket", comment: "Gear menu"), action: actions.quit)
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text("Settings", comment: "Gear menu button"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}
