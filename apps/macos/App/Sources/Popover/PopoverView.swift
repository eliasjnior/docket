import DocketActivity
import DocketCore
import DocketStores
import SwiftUI

/// The popover of `docs/05-design.md` §5: header, banners, tabs, filters, then the list or a full screen.
struct PopoverView: View {
    static let width: CGFloat = 460
    static let boardWidth: CGFloat = 780

    let watch: WatchStore
    @Bindable var model: PopoverModel
    let permission: NotificationPermission
    let actions: PopoverActions

    private var maxHeight: CGFloat {
        min(640, (NSScreen.main?.visibleFrame.height ?? 800) - 40)
    }

    private var columns: Bool { watch.config.popoverLayout == .columns }

    /// Left to right when moving to a tab on the right, right to left when moving back.
    private var slide: AnyTransition {
        let forward = model.slidesForward
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }
    /// With *Mine* as a board the popover keeps the board's width on every tab, so a switch does not resize it.
    private var isBoard: Bool { !columns && watch.config.mineLayout == .board }
    private var width: CGFloat {
        columns
            ? ColumnsView.widths(board: watch.config.mineLayout == .board, involvedFolded: model.involvedFolded)
                .reduce(2, +)
            : isBoard ? Self.boardWidth : Self.width
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date.addingTimeInterval(watch.snapshot.state.lastPoll?.serverTimeOffset ?? 0)
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    PopoverHeader(watch: watch, actions: actions, now: context.date)
                    Banners(watch: watch, permission: permission, actions: actions, now: context.date)
                    if FullScreen.for(watch: watch) == nil {
                        if !columns { TabBar(watch: watch, model: model) }
                        FilterBar(watch: watch, model: model, actions: actions)
                    }
                    Divider()
                }
                if let screen = FullScreen.for(watch: watch) {
                    FullScreenView(screen: screen, actions: actions).padding(20)
                } else if columns {
                    ColumnsView(watch: watch, model: model, actions: actions, now: now)
                        .frame(maxHeight: .infinity)
                } else {
                    // A new scroll view per tab and sub-tab, so a switch slides the old list out one side and the new
                    // one in from the other. Inside a scroll view the same transition did not run.
                    ZStack {
                        ScrollView {
                            SectionsView(watch: watch, model: model, actions: actions, now: now)
                                .padding(.bottom, 6)
                        }
                        .id("\(model.tab)-\(model.triage)")
                        .transition(slide)
                    }
                    .frame(maxHeight: .infinity)
                    .clipped()
                }
            }
            // One height whichever tab is open: the list takes what is left under the header and the filters.
            // Measuring them instead let the popover change size for a frame on each switch.
            .frame(height: FullScreen.for(watch: watch) == nil ? maxHeight : nil, alignment: .top)
        }
        .frame(width: width)
        // Solid, not the popover's vibrant material: through vibrancy the text read pale and see-through.
        .background(Color(nsColor: .windowBackgroundColor))
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

    /// What is on screen: a collapsed group's rows are not.
    static func visibleItems(_ sections: Sections, model: PopoverModel, layout: Config.MineLayout)
        -> [WatchedPullRequest]
    {
        switch model.tab {
        case .reviewRequested:
            sections.reviewRequested(model.triage).filter { !model.collapsedRepositories.contains($0.repository) }
                .flatMap { drawn($0.items, model) }
        case .mine where layout == .board:
            // In the order the board shows them: column by column, repository by repository.
            sections.mineListGroups.flatMap { group in
                Sections.byRepository(group.items).filter { !model.isCollapsed(group.kind, $0.repository) }
                    .flatMap { drawn($0.items, model) }
            }
        case .mine:
            sections.mineListGroups.filter { !model.collapsedMineGroups.contains($0.kind) }
                .flatMap { drawn($0.items, model) }
        case .involved: drawn(sections.involved, model)
        case .ignored: sections.ignored
        }
    }

    /// The rows a list draws: a folded stack block's rows are not among them.
    private static func drawn(_ items: [WatchedPullRequest], _ model: PopoverModel) -> [WatchedPullRequest] {
        RowSegment.split(items).flatMap { segment -> [WatchedPullRequest] in
            switch segment {
            case .row(let item): [item]
            case .stack(let stack): model.collapsedStacks.contains(stack.id) ? [] : stack.items
            }
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
        if watch.config.popoverLayout == .columns, model.involvedFolded { tabs = [.reviewRequested, .mine] }
        guard let index = tabs.firstIndex(of: model.tab) else { return .ignored }
        model.switchTo(tabs[(index + step + tabs.count) % tabs.count])
        return .handled
    }
}

/// The logo, the name, refresh and settings. The refresh symbol spinning is the only progress signal.
struct PopoverHeader: View {
    let watch: WatchStore
    let actions: PopoverActions
    var now = Date()

    var body: some View {
        HStack(spacing: 8) {
            AppIconView(size: 22)
            Text(verbatim: "Docket").font(.headline)
            Spacer()
            PollStatusIcon(watch: watch, now: now, retry: actions.refresh)
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
                Button(String(localized: "Settings", comment: "Gear menu"), action: actions.openSettings)
                Button(String(localized: "Check for Updates", comment: "Gear menu"), action: actions.checkForUpdates)
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
