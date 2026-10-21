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
                tagMenu
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
            if let repository = model.repositoryFilter {
                FilterToken(text: repository) { model.repositoryFilter = nil }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
