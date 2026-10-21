import Foundation

/// Notification Center, at its edge (`docs/03-architecture.md` §7).
public protocol NotificationSink: Sendable {
    func deliver(_ notifications: [PlannedNotification]) async
    func authorization() async -> NotificationAuthorization
    func requestAuthorization() async -> NotificationAuthorization
}

public enum NotificationAuthorization: String, Hashable, Sendable {
    case allowed
    case notAsked
    case denied
}
