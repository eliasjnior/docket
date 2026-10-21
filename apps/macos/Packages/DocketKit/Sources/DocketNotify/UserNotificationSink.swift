import DocketCore
import Foundation
import UserNotifications
import os

/// `NotificationSink` over `UNUserNotificationCenter` (`docs/05-design.md` §8).
public struct UserNotificationSink: NotificationSink {
    public static let openAction = "docket.open"
    public static let openDocketAction = "docket.openDocket"
    public static let muteRemindersAction = "docket.muteReminders"

    private let now: @Sendable () -> Date
    private let log = Logger(subsystem: "com.eliasjnior.docket", category: "notify")

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    private var center: UNUserNotificationCenter { .current() }

    /// Registered at launch: one category per kind of click target.
    public static func registerCategories() {
        let open = UNNotificationAction(
            identifier: openAction, title: String(localized: "Open", comment: "Notification action"), options: [])
        let openDocket = UNNotificationAction(
            identifier: openDocketAction, title: String(localized: "Open Docket", comment: "Notification action"),
            options: [.foreground])
        let mute = UNNotificationAction(
            identifier: muteRemindersAction, title: String(localized: "Mute Reminders", comment: "Notification action"),
            options: [])
        typealias Category = ComposedNotification.Category
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(
                identifier: Category.single.rawValue, actions: [open, openDocket],
                intentIdentifiers: []),
            UNNotificationCategory(
                identifier: Category.group.rawValue, actions: [openDocket], intentIdentifiers: []),
            UNNotificationCategory(
                identifier: Category.reminder.rawValue, actions: [open, mute],
                intentIdentifiers: []),
            UNNotificationCategory(
                identifier: Category.digest.rawValue, actions: [openDocket], intentIdentifiers: []),
        ])
    }

    public func deliver(_ notifications: [PlannedNotification]) async {
        guard await authorization() == .allowed else { return }
        let now = now()
        for planned in notifications {
            let composed = ComposedNotification(planned, now: now)
            let content = UNMutableNotificationContent()
            content.title = composed.title
            content.subtitle = composed.subtitle
            content.body = composed.body
            content.categoryIdentifier = composed.category.rawValue
            content.threadIdentifier = composed.threadIdentifier
            if let repository = composed.repository { content.summaryArgument = repository }
            content.sound = .default
            content.interruptionLevel = .active
            content.userInfo = NotificationClick.userInfo(for: composed)
            let request = UNNotificationRequest(identifier: composed.identifier, content: content, trigger: nil)
            do {
                try await center.add(request)
            } catch {
                log.error("Could not deliver: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func authorization() async -> NotificationAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .allowed
        case .denied: .denied
        case .notDetermined: .notAsked
        @unknown default: .denied
        }
    }

    public func requestAuthorization() async -> NotificationAuthorization {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        return await authorization()
    }
}

/// What a click on a notification asks for (`docs/02-activity-detection.md` §7.4).
public enum NotificationClick: Hashable, Sendable {
    case open(URL)
    case popover(repository: String?)
    case muteReminders(pullRequestID: String, ref: String?)

    static func userInfo(for composed: ComposedNotification) -> [String: String] {
        var info: [String: String] = [:]
        info["url"] = composed.url?.absoluteString
        info["repository"] = composed.repository
        info["pullRequestID"] = composed.pullRequestID
        info["ref"] = composed.pullRequestID == nil ? nil : composed.subtitle.replacingOccurrences(of: " #", with: "#")
        return info
    }

    public static func route(action: String, userInfo: [AnyHashable: Any]) -> NotificationClick {
        let url = (userInfo["url"] as? String).flatMap(URL.init(string:))
        let repository = userInfo["repository"] as? String
        switch action {
        case UserNotificationSink.muteRemindersAction:
            if let id = userInfo["pullRequestID"] as? String {
                return .muteReminders(pullRequestID: id, ref: userInfo["ref"] as? String)
            }
            return .popover(repository: repository)
        case UserNotificationSink.openDocketAction:
            return .popover(repository: repository)
        default:
            if let url { return .open(url) }
            return .popover(repository: repository)
        }
    }
}

/// Bridges the delegate's callbacks, which arrive off the main actor, to the app.
public final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let handle: @Sendable (NotificationClick) -> Void

    public init(handle: @escaping @Sendable (NotificationClick) -> Void) {
        self.handle = handle
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        handle(
            NotificationClick.route(
                action: response.actionIdentifier, userInfo: response.notification.request.content.userInfo))
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
