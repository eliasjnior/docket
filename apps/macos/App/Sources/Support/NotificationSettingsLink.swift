import AppKit

/// System Settings → Notifications → Docket.
enum NotificationSettingsLink {
    @MainActor
    static func open() {
        let identifier = Bundle.main.bundleIdentifier ?? "com.eliasjnior.docket"
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(identifier)")
        if let url { NSWorkspace.shared.open(url) }
    }
}
