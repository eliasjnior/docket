import AppKit

@MainActor
final class StatusBarController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    init() {
        if let button = item.button {
            let image = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: "Docket")
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Docket", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
    }
}
