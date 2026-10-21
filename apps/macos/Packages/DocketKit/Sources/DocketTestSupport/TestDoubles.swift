import DocketCore
import Foundation
import Synchronization

/// Keeps what would have been handed to Notification Center; the edge is Notification Center itself.
public final class RecordingNotificationSink: NotificationSink {
    private let delivered = Mutex<[[PlannedNotification]]>([])
    private let status: NotificationAuthorization

    public init(status: NotificationAuthorization = .allowed) {
        self.status = status
    }

    /// Every batch delivered, one per poll that delivered anything.
    public var batches: [[PlannedNotification]] { delivered.withLock { $0 } }
    public var all: [PlannedNotification] { batches.flatMap { $0 } }

    public func deliver(_ notifications: [PlannedNotification]) async {
        guard !notifications.isEmpty else { return }
        delivered.withLock { $0.append(notifications) }
    }

    public func authorization() async -> NotificationAuthorization { status }
    public func requestAuthorization() async -> NotificationAuthorization { status }
}

/// A clock tests set by hand. `sleep` waits until cancelled, so a started loop polls once and stops.
public final class ManualClock: Sendable {
    private let current: Mutex<Date>

    public init(_ start: Date = Fixtures.now) {
        current = Mutex(start)
    }

    public func now() -> Date { current.withLock { $0 } }

    public func advance(_ interval: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(interval) }
    }

    public func set(_ date: Date) {
        current.withLock { $0 = date }
    }

    public func sleep(for interval: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(86400 * 365))
    }
}
