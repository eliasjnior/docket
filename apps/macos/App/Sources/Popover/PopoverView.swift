import DocketActivity
import DocketCore
import DocketStores
import SwiftUI

/// The popover of `docs/05-design.md` §5: header, banners, then the sections or a full screen.
struct PopoverView: View {
    let watch: WatchStore
    @Bindable var model: PopoverModel
    let permission: NotificationPermission
    let actions: PopoverActions

    private var maxHeight: CGFloat {
        min(600, (NSScreen.main?.visibleFrame.height ?? 800) - 40)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date.addingTimeInterval(watch.snapshot.state.lastPoll?.serverTimeOffset ?? 0)
            VStack(spacing: 0) {
                PopoverHeader(watch: watch, model: model, actions: actions, now: context.date)
                Banners(watch: watch, permission: permission, actions: actions, now: context.date)
                if FullScreen.for(watch: watch) == nil {
                    TabBar(watch: watch, model: model)
                }
                Divider()
                if let screen = FullScreen.for(watch: watch) {
                    FullScreenView(screen: screen, actions: actions).padding(20)
                } else {
                    ScrollView {
                        SectionsView(watch: watch, model: model, actions: actions, now: now)
                            .padding(.vertical, 4)
                    }
                    .frame(maxHeight: maxHeight - 80)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(width: 380)
        .onExitCommand {
            if !model.clearFilter() { actions.close() }
        }
        .background {
            Button("") { actions.refresh() }.keyboardShortcut("r").hidden()
            Button("") { actions.openSettings() }.keyboardShortcut(",").hidden()
        }
    }
}

struct PopoverHeader: View {
    let watch: WatchStore
    @Bindable var model: PopoverModel
    let actions: PopoverActions
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(verbatim: "Docket").font(.headline)
                Spacer()
                Button(action: actions.refresh) {
                    Image(systemName: "arrow.clockwise")
                        .symbolEffect(.rotate, isActive: watch.isPolling)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Refresh", comment: "Refresh button"))
                .accessibilityLabel(Text("Refresh", comment: "Refresh button"))
                Menu {
                    Button(String(localized: "Settings…", comment: "Gear menu"), action: actions.openSettings)
                    Button(
                        String(localized: "Check for Updates…", comment: "Gear menu"), action: actions.checkForUpdates)
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
            if watch.isPolling {
                Text("Updating…", comment: "Header while a poll runs").font(.subheadline).foregroundStyle(
                    Color.textSecondary)
            } else if watch.isStale(now: now), let fetchedAt = watch.fetchedAt {
                let minutes = max(1, Int(now.timeIntervalSince(fetchedAt) / 60))
                Text("Updated \(minutes) min ago", comment: "Header when the list is older than two poll intervals")
                    .font(.subheadline).foregroundStyle(Color.textSecondary)
            }
            HStack(spacing: 12) {
                repositoryMenu
                tagMenu
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// Repositories in the list, most rows first (FR-82).
    private var repositoryMenu: some View {
        let counts = Dictionary(grouping: watch.items, by: { $0.pullRequest.repository }).mapValues(\.count)
        let repositories = counts.keys.sorted { (counts[$0] ?? 0, $1) > (counts[$1] ?? 0, $0) }
        return Menu {
            Button(String(localized: "All repositories", comment: "Repository filter")) { model.repositoryFilter = nil }
            if !repositories.isEmpty { Divider() }
            ForEach(repositories, id: \.self) { repository in
                Button("\(repository) (\(counts[repository] ?? 0))") { model.repositoryFilter = repository }
            }
        } label: {
            Text(
                verbatim: Self.short(model.repositoryFilter)
                    ?? String(localized: "All repositories", comment: "Repository filter"))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.subheadline)
    }

    private static func short(_ repository: String?) -> String? {
        guard let repository else { return nil }
        return repository.count > 32 ? String(repository.prefix(31)) + "…" : repository
    }

    private var tagMenu: some View {
        Menu {
            Button(String(localized: "All tags", comment: "Tag filter")) { model.tagFilter = nil }
            if !watch.tagsInUse.isEmpty { Divider() }
            ForEach(watch.tagsInUse, id: \.self) { tag in
                Button(tag) { model.tagFilter = tag }
            }
        } label: {
            Text(model.tagFilter ?? String(localized: "All tags", comment: "Tag filter"))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.subheadline)
    }
}

struct FilterToken: View {
    let text: String
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: text)
            Button(action: clear) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Clear filter", comment: "Repository filter token"))
        }
        .font(.subheadline)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.fillTag))
    }
}

/// The four sections as tabs; Ignored only while something is ignored.
struct TabBar: View {
    let watch: WatchStore
    @Bindable var model: PopoverModel

    var body: some View {
        let sections = watch.sections(tag: model.tagFilter, repository: model.repositoryFilter)
        HStack(spacing: 4) {
            tab(
                .reviewRequested, String(localized: "Review requested", comment: "Tab"), sections.reviewRequestedCount,
                marked: sections.reviewRequested.flatMap(\.items).contains(where: \.isMarked))
            tab(
                .mine, String(localized: "Mine", comment: "Tab"), sections.mine.count,
                marked: sections.mine.contains(where: \.isMarked))
            tab(
                .involved, String(localized: "Involved", comment: "Tab"), sections.involved.count,
                marked: sections.involved.contains(where: \.isMarked))
            if !sections.ignored.isEmpty || model.tab == .ignored {
                tab(.ignored, String(localized: "Ignored", comment: "Tab"), sections.ignored.count, marked: false)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private func tab(_ section: PopoverModel.Section, _ title: String, _ count: Int, marked: Bool) -> some View {
        let selected = model.tab == section
        return Button {
            model.tab = section
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: title).lineLimit(1)
                Text(verbatim: "\(count)").monospacedDigit().foregroundStyle(Color.textSecondary)
                if marked {
                    Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(Color.accentMarked)
                }
            }
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(selected ? Color.fillTag : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(Text(verbatim: "\(title), \(count)"))
    }
}
