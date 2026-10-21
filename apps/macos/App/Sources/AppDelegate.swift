import AppKit
import DocketCore
import DocketStores
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var statusBar: StatusBarController?
    private var settings: SettingsWindowController?
    private let popover = PopoverModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment()
        self.environment = environment
        environment.handleNotifications { [weak self] route in
            switch route {
            case .open(let url): NSWorkspace.shared.open(url)
            case .popover(let repository):
                self?.popover.repositoryFilter = repository
                self?.statusBar?.show()
            }
        }
        let account = AccountSettingsModel(
            locate: { await environment.tokens.location() },
            chooseLocation: { [weak self] in self?.chooseGhLocation() },
            retry: { environment.retryAuthentication() })
        settings = SettingsWindowController {
            AnyView(
                SettingsView(
                    watch: environment.watch, configStore: environment.configStore, account: account,
                    permission: environment.permission,
                    requestPermission: { Task { await environment.requestNotificationPermission() } },
                    checkRepository: { await environment.repositoryExists($0) }))
        }
        let content = PopoverView(
            watch: environment.watch, model: popover, permission: environment.permission,
            actions: popoverActions(environment))
        var shownMarks: [String] = []
        statusBar = StatusBarController(
            watch: environment.watch, content: content, menuItems: statusMenu(),
            onOpen: {
                shownMarks = environment.watch.snapshot.state.marked
                Task {
                    await environment.refreshNotificationPermission()
                    await environment.poller.pollIfOlder(than: 30)
                }
            },
            onClose: {
                // Marks shown in this opening are cleared; one that arrived while open stays (FR-46).
                let seen = Set(shownMarks)
                let openedAt = Date()
                Task {
                    await environment.poller.updateState { state in
                        state.marked.removeAll(where: seen.contains)
                        state.popoverOpenedAt = openedAt
                    }
                }
            })
        Task {
            await environment.start()
            await environment.requestNotificationPermission()
        }
    }

    private func statusMenu() -> [NSMenuItem] {
        let refresh = NSMenuItem(
            title: String(localized: "Refresh", comment: "Status item menu"), action: #selector(refresh),
            keyEquivalent: "r")
        let settings = NSMenuItem(
            title: String(localized: "Settings…", comment: "Status item menu"), action: #selector(openSettings),
            keyEquivalent: ",")
        let quit = NSMenuItem(
            title: String(localized: "Quit Docket", comment: "Status item menu"),
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        [refresh, settings].forEach { $0.target = self }
        return [refresh, settings, .separator(), quit]
    }

    @objc private func refresh() {
        guard let environment else { return }
        Task { await environment.poller.pollNow() }
    }

    @objc private func openSettings() {
        statusBar?.close()
        settings?.show()
    }

    private func popoverActions(_ environment: AppEnvironment) -> PopoverActions {
        let configStore = environment.configStore
        let popover = popover
        let row = RowActions(
            open: { NSWorkspace.shared.open($0) },
            copy: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            },
            filterRepository: { popover.repositoryFilter = $0 },
            filterTag: { popover.tagFilter = $0 },
            editTags: { popover.editingTags = $0 },
            setMute: { item, choice in
                configStore.update { config in
                    if let choice {
                        config.mutes[item.id] = Config.MuteEntry(
                            ref: item.pullRequest.ref, scope: choice == .all ? .all : .reminders, mutedAt: Date())
                    } else {
                        config.mutes[item.id] = nil
                    }
                }
            },
            setIgnored: { item, ignored in
                configStore.update { config in
                    if ignored {
                        config.ignored[item.id] = Config.IgnoreEntry(ref: item.pullRequest.ref, ignoredAt: Date())
                        config.mutes[item.id] = nil
                    } else {
                        config.ignored[item.id] = nil
                    }
                }
            })
        return PopoverActions(
            refresh: { [weak self] in self?.refresh() },
            openSettings: { [weak self] in self?.openSettings() },
            checkForUpdates: { [weak self] in self?.openSettings() },
            quit: { NSApp.terminate(nil) },
            retry: { environment.retryAuthentication() },
            chooseGhLocation: { [weak self] in self?.chooseGhLocation() },
            dismissBaselineNotice: {
                Task { await environment.poller.updateState { $0.baselineNoticeDismissed = true } }
            },
            close: { [weak self] in self?.statusBar?.close() },
            row: row)
    }

    private func chooseGhLocation() {
        guard let environment else { return }
        let panel = NSOpenPanel()
        panel.message = String(localized: "Choose the gh executable", comment: "Open panel message")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        environment.configStore.update { $0.ghPath = url.path }
        environment.retryAuthentication()
    }
}
