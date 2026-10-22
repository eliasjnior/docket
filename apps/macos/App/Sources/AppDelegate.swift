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
    private var updateWindows: UpdateWindows?
    private let shortcut = GlobalShortcut()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment()
        self.environment = environment
        environment.handleNotifications { [weak self] route in
            switch route {
            case .open(let url):
                NSWorkspace.shared.open(url)
                // A notification about one pull request opens it, so the row is seen (spec §4).
                let seen = environment.watch.items.filter { item in
                    let base = item.pullRequest.url.absoluteString
                    guard url.absoluteString.hasPrefix(base) else { return false }
                    return url.absoluteString.dropFirst(base.count).first.map { "#/?".contains($0) } ?? true
                }
                Task { await environment.poller.markSeen(seen.map(\.id)) }
            case .popover(let repository):
                if let repository { self?.popover.show(repository: repository) }
                self?.statusBar?.show()
            }
        }
        let updateWindows = UpdateWindows(updates: environment.updates, info: environment.info)
        self.updateWindows = updateWindows
        settings = makeSettings(environment, windows: updateWindows)
        statusBar = makeStatusBar(environment)
        Task {
            await environment.start()
            await FocusBridge.connect { hold in await environment.poller.setHold(hold) }
            environment.reconcileLoginItem()
            await environment.requestNotificationPermission()
            if let lastShown = await environment.takeLastShownVersion(), lastShown < environment.info.semanticVersion {
                updateWindows.showWhatsNew(since: lastShown)
            }
        }
        environment.updates.relaunch = { NSApp.terminate(nil) }
        environment.updates.startAutomaticChecks()
        observeUpdates(environment, windows: updateWindows)
        observeContinuously(environment.configStore) { [weak self] store in
            self?.shortcut.register(store.config.shortcut) { self?.statusBar?.show() }
        }
    }

    private func makeSettings(_ environment: AppEnvironment, windows updateWindows: UpdateWindows)
        -> SettingsWindowController
    {
        let account = AccountSettingsModel(
            locate: { await environment.tokens.location() },
            chooseLocation: { [weak self] in self?.chooseGhLocation() },
            retry: { environment.retryAuthentication() })
        return SettingsWindowController {
            AnyView(
                SettingsView(
                    watch: environment.watch, configStore: environment.configStore, account: account,
                    permission: environment.permission,
                    requestPermission: { Task { await environment.requestNotificationPermission() } },
                    checkRepository: { await environment.repositoryExists($0) }, updates: environment.updates,
                    info: environment.info, loginItem: environment.loginItem, dataFolder: environment.paths.root,
                    showWhatsNew: { updateWindows.showWhatsNew() }, showPrompt: { updateWindows.showPrompt() }))
        }
    }

    private func makeStatusBar(_ environment: AppEnvironment) -> StatusBarController {
        let content = PopoverView(
            watch: environment.watch, model: popover, permission: environment.permission,
            actions: popoverActions(environment))
        var shownMarks: [String] = []
        return StatusBarController(
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
    }

    /// A newly found update shows the prompt once, unless updates install by themselves.
    private func observeUpdates(_ environment: AppEnvironment, windows: UpdateWindows) {
        var announced: String?
        observeContinuously(environment.updates) { updates in
            guard let update = updates.availableUpdate, update.version.description != announced else { return }
            announced = update.version.description
            if !environment.configStore.config.updates.automaticInstall { windows.showPrompt() }
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
        let row = rowActions(environment)
        return PopoverActions(
            refresh: { [weak self] in self?.refresh() },
            openSettings: { [weak self] in self?.openSettings() },
            checkForUpdates: { [weak self] in
                self?.statusBar?.close()
                Task {
                    await environment.updates.check(userInitiated: true)
                    self?.updateWindows?.showPrompt()
                }
            },
            quit: { NSApp.terminate(nil) },
            retry: { environment.retryAuthentication() },
            chooseGhLocation: { [weak self] in self?.chooseGhLocation() },
            launchAtLogin: { environment.setLaunchAtLogin($0) },
            deliverHeld: { Task { await environment.poller.setHold(false) } },
            dismissBaselineNotice: {
                Task { await environment.poller.updateState { $0.baselineNoticeDismissed = true } }
            },
            close: { [weak self] in self?.statusBar?.close() },
            row: row)
    }

    private func rowActions(_ environment: AppEnvironment) -> RowActions {
        let configStore = environment.configStore
        let popover = popover
        return RowActions(
            open: { NSWorkspace.shared.open($0) },
            copy: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            },
            filterRepository: { repository in
                if !popover.filter.contains(repository, in: .repository) {
                    popover.filter.toggle(repository, in: .repository)
                }
            },
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
            },
            markSeen: { ids in Task { await environment.poller.markSeen(ids) } })
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
