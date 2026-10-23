import AppKit
import SwiftUI

/// The floating panel the cards live in: top right of the active screen, over full-screen apps, never
/// taking focus from the app in front (`docs/05-design.md` §8.1).
@MainActor
final class CardPanelController {
    let stack = CardStack()
    private var panel: NSPanel?
    private var actions: CardActions?
    private var resize: Task<Void, Never>?

    func configure(_ actions: CardActions) {
        self.actions = actions
    }

    func show(_ cards: [NotificationCard], sound: Bool) {
        guard !cards.isEmpty, let actions else { return }
        stack.push(cards)
        let panel = panel ?? makePanel(actions)
        place(panel)
        panel.orderFrontRegardless()
        // An approval gets its own sound, so good news is told apart without looking.
        if sound { NSSound(named: cards.contains { $0.kind == .approved } ? "Hero" : "Glass")?.play() }
    }

    private func makePanel(_ actions: CardActions) -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = FirstClickHostingView(rootView: CardStackView(stack: stack, actions: actions))
        self.panel = panel
        observeContinuously(stack) { [weak self] stack in
            _ = stack.cards
            self?.stackChanged()
        }
        return panel
    }

    /// A shrinking stack waits for the removal to fade before the window gets smaller, or the card is cut off.
    private func stackChanged() {
        guard let panel else { return }
        resize?.cancel()
        if stack.cards.isEmpty {
            resize = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, stack.cards.isEmpty else { return }
                panel.orderOut(nil)
            }
            return
        }
        let grows = (panel.contentView?.fittingSize.height ?? 0) >= panel.frame.height
        if grows {
            place(panel)
        } else {
            resize = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                place(panel)
            }
        }
    }

    private func place(_ panel: NSPanel) {
        guard let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let origin = NSPoint(x: visible.maxX - size.width - 4, y: visible.maxY - size.height - 4)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

/// A click on a card acts at once, although the panel never becomes the key window.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
