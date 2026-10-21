import Carbon
import DocketCore

/// The global shortcut that opens the popover (FR-48). Carbon's hot keys need no Accessibility permission,
/// unlike an `NSEvent` global monitor (`docs/08-stack.md`).
@MainActor
final class GlobalShortcut {
    private static var action: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register(_ shortcut: Config.Shortcut, action: @escaping () -> Void) {
        unregister()
        Self.action = action
        guard let modifiers = Self.modifiers(shortcut) else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { GlobalShortcut.action?() } }
                return noErr
            }, 1, &type, nil, &handler)
        let identifier = EventHotKeyID(signature: OSType(0x444B_5420), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_D), modifiers, identifier, GetApplicationEventTarget(), 0, &hotKey)
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }

    private static func modifiers(_ shortcut: Config.Shortcut) -> UInt32? {
        switch shortcut {
        case .off: nil
        case .controlOptionCommandD: UInt32(controlKey | optionKey | cmdKey)
        case .optionCommandD: UInt32(optionKey | cmdKey)
        case .controlOptionD: UInt32(controlKey | optionKey)
        }
    }

    static func label(_ shortcut: Config.Shortcut) -> String {
        switch shortcut {
        case .off: String(localized: "Off", comment: "Global shortcut option")
        case .controlOptionCommandD: "⌃⌥⌘D"
        case .optionCommandD: "⌥⌘D"
        case .controlOptionD: "⌃⌥D"
        }
    }
}
