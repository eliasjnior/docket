import AppKit
import DocketActivity
import DocketStores
import SwiftUI

/// The status item of `docs/05-design.md` §4: the icon, the "needs you" count, and the popover.
@MainActor
final class StatusBarController: NSObject {
    private let watch: WatchStore
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let menu = NSMenu()
    private let onOpen: () -> Void

    init(watch: WatchStore, content: some View, menuItems: [NSMenuItem], onOpen: @escaping () -> Void) {
        self.watch = watch
        self.onOpen = onOpen
        super.init()
        popover.behavior = .transient
        popover.setHostedContent(content)
        menuItems.forEach(menu.addItem)
        if let button = item.button {
            button.target = self
            button.action = #selector(click)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
        observeContinuously(self) { $0.render() }
    }

    var isShown: Bool { popover.isShown }

    func show() {
        guard let button = item.button, !popover.isShown else { return }
        popover.show(below: button)
        onOpen()
    }

    func close() {
        popover.performClose(nil)
    }

    @objc private func click() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
            return
        }
        if popover.isShown { close() } else { show() }
    }

    private func render() {
        guard let button = item.button else { return }
        let image = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: nil)
        image?.isTemplate = true
        button.image = image

        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        let title = NSMutableAttributedString()
        let count = watch.count
        let dimmed: Bool
        let tooltip: String
        switch (watch.account, watch.problem) {
        case (.ghNotFound, _), (.signedOut, _), (.missingScopes, _):
            dimmed = false
            tooltip = String(
                localized: "Docket needs attention: \(Self.reason(watch.account))", comment: "Status item tooltip")
            title.append(Self.attention(font: font))
        case (.loading, _) where !watch.hasCache:
            dimmed = false
            tooltip = String(localized: "Loading pull requests", comment: "Status item tooltip")
        case (_, .offline):
            dimmed = true
            tooltip = String(
                localized: "Offline. Showing data from \(Banners.time(watch.fetchedAt ?? .now, now: .now))",
                comment: "Status item tooltip")
            title.append(Self.count(count, font: font))
        case (_, .rateLimited(let until)):
            dimmed = true
            tooltip = String(
                localized: "Paused by GitHub's rate limit until \(Banners.time(until, now: .now))",
                comment: "Status item tooltip")
            title.append(Self.count(count, font: font))
        case (_, .failed(let at)) where watch.isStale(now: .now):
            dimmed = false
            tooltip = String(
                localized: "Last update failed at \(Banners.time(at, now: .now))", comment: "Status item tooltip")
            title.append(Self.count(count, font: font))
            title.append(Self.attention(font: font))
        default:
            dimmed = false
            tooltip =
                count == 0
                ? String(localized: "Nothing needs you", comment: "Status item tooltip")
                : String(localized: "\(count) pull requests need you", comment: "Status item tooltip")
            title.append(Self.count(count, font: font))
        }
        button.attributedTitle = title
        button.appearsDisabled = dimmed
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
    }

    private static func count(_ count: Int, font: NSFont) -> NSAttributedString {
        guard let label = Count.label(count) else { return NSAttributedString() }
        return NSAttributedString(string: " \(label)", attributes: [.font: font])
    }

    private static func attention(font: NSFont) -> NSAttributedString {
        let attachment = NSTextAttachment()
        let configuration = NSImage.SymbolConfiguration(pointSize: font.capHeight + 2, weight: .regular)
        let image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        attachment.image = image
        let text = NSMutableAttributedString(string: " ", attributes: [.font: font])
        text.append(NSAttributedString(attachment: attachment))
        return text
    }

    private static func reason(_ account: AccountState) -> String {
        switch account {
        case .ghNotFound: String(localized: "GitHub CLI not found", comment: "Status item tooltip reason")
        case .signedOut: String(localized: "GitHub CLI not signed in", comment: "Status item tooltip reason")
        case .missingScopes:
            String(localized: "GitHub CLI token is missing scopes", comment: "Status item tooltip reason")
        case .loading, .ready: ""
        }
    }
}
