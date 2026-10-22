import AppKit
import SwiftUI

/// The settings window: a native toolbar of tabs, as macOS's own settings, each tab a hosted SwiftUI form. A
/// SwiftUI `TabView` in a plain window drew its own segmented bar instead, crowded against the title bar.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let makeTabs: () -> [SettingsTab]

    init(makeTabs: @escaping () -> [SettingsTab]) {
        self.makeTabs = makeTabs
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.allowUserInteraction]
        for tab in makeTabs() {
            let controller = NSHostingController(rootView: tab.content)
            controller.sizingOptions = [.preferredContentSize]
            controller.title = tab.title
            let item = NSTabViewItem(viewController: controller)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.title = String(localized: "Docket Settings", comment: "Settings window title")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        return window
    }
}
