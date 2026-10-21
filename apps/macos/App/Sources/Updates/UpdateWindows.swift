import AppKit
import DocketStores
import DocketUpdate
import SwiftUI

@MainActor
final class UpdateWindows {
    private let updates: UpdateStore
    private let info: AppInfo
    private var whatsNew: NSWindow?
    private var prompt: NSWindow?

    init(updates: UpdateStore, info: AppInfo) {
        self.updates = updates
        self.info = info
    }

    /// FR-94: the entries between the last shown version and the running one, once after an update.
    func showWhatsNew(since lastSeen: SemanticVersion? = nil) {
        let all = Changelog.parse(Self.bundledChangelog())
        var entries = Changelog.entries(all, after: lastSeen, upTo: info.semanticVersion)
        if entries.isEmpty { entries = Array(all.prefix(3)) }
        whatsNew?.close()
        whatsNew = present(
            title: String(localized: "What's New", comment: "Window title"),
            view: WhatsNewView(entries: entries) { [weak self] in self?.whatsNew?.close() })
    }

    func showPrompt() {
        if let prompt, prompt.isVisible {
            prompt.makeKeyAndOrderFront(nil)
            return
        }
        let close: () -> Void = { [weak self] in self?.prompt?.close() }
        prompt = present(
            title: String(localized: "Software Update", comment: "Window title"),
            view: UpdatePromptView(updates: updates, currentVersion: info.version, close: close))
    }

    private func present(title: String, view: some View) -> NSWindow {
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        // Size the window from its content before centering, or it is centered as an empty window.
        controller.view.layoutSubtreeIfNeeded()
        window.setContentSize(controller.view.fittingSize)
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        return window
    }

    static func bundledChangelog() -> String {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
