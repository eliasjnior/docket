import AppKit
import SwiftUI

extension NSPopover {
    @MainActor private static weak var current: NSPopover?

    /// Hosts a SwiftUI view whose size the popover follows as the content changes.
    func setHostedContent(_ view: some View) {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]
        contentViewController = controller
    }

    /// Shows the popover under a status item. The content is laid out first: a popover shown before its
    /// SwiftUI content has a size is positioned for a zero-sized view and ends up off screen.
    func show(below button: NSStatusBarButton) {
        if let previous = Self.current, previous !== self, previous.isShown {
            previous.performClose(nil)
        }
        if let view = contentViewController?.view {
            view.layoutSubtreeIfNeeded()
            let size = view.fittingSize
            if size.width > 0, size.height > 0 {
                contentSize = size
            }
        }
        NSApp.activate()
        show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        contentViewController?.view.window?.makeKey()
        Self.current = self
    }
}
