import AppKit
import DocketStores
import SwiftUI

/// The setup window, one at a time, brought forward when asked again.
@MainActor
final class SetupWindow {
    private let setup: SetupStore
    private let chooseGhLocation: () -> Void
    private var window: NSWindow?

    init(setup: SetupStore, chooseGhLocation: @escaping () -> Void) {
        self.setup = setup
        self.chooseGhLocation = chooseGhLocation
    }

    func show() {
        if let window, window.isVisible {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = SetupView(setup: setup, chooseGhLocation: chooseGhLocation) { [weak self] in
            self?.window?.close()
        }
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.title = String(localized: "Set Up Docket", comment: "Setup window title")
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        controller.view.layoutSubtreeIfNeeded()
        window.setContentSize(controller.view.fittingSize)
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
