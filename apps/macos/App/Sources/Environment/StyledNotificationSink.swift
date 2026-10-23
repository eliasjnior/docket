import DocketCore
import DocketNotify
import Foundation

/// The poller's `NotificationSink`: Docket's cards or Notification Center, as `config.notifications.style`
/// says at the moment of delivery (`docs/05-design.md` §8).
struct StyledNotificationSink: NotificationSink {
    let system: UserNotificationSink
    let settings: @Sendable () async -> Config.Notifications
    let present: @MainActor @Sendable ([NotificationCard], _ sound: Bool) -> Void

    func deliver(_ notifications: [PlannedNotification]) async {
        let settings = await settings()
        guard settings.style == .card else {
            await system.deliver(notifications)
            return
        }
        let now = Date()
        let cards = notifications.map {
            NotificationCard(ComposedNotification($0, now: now), settings: settings)
        }
        await present(cards, settings.sound)
    }

    func authorization() async -> NotificationAuthorization {
        await system.authorization()
    }

    func requestAuthorization() async -> NotificationAuthorization {
        await system.requestAuthorization()
    }
}

extension NotificationCard {
    /// `settings` decide whether a card about something waiting on you stays, and how long the others do.
    init(_ composed: ComposedNotification, settings: Config.Notifications) {
        let single = composed.pullRequestTitle != nil
        self.init(
            id: composed.identifier, kind: Kind(composed), headline: composed.title,
            title: composed.pullRequestTitle,
            detail: single
                ? [composed.subtitle, composed.via].compactMap { $0 }.joined(separator: " · ") : composed.body,
            repository: composed.repository, url: composed.url, pullRequestID: composed.pullRequestID,
            isSticky: settings.keepCardsUntilActedOn && composed.isSticky,
            lifetime: TimeInterval(settings.cardSeconds))
    }
}

extension NotificationCard.Kind {
    init(_ composed: ComposedNotification) {
        if composed.category == .reminder {
            self = .reminder
            return
        }
        switch composed.kind {
        case .reviewRequested: self = .reviewRequested
        case .reviewSubmitted: self = Self.review(composed.decision)
        case .commentAdded: self = .comment
        case .threadReply: self = .reply
        case .checksFailed: self = .checksFailed
        case .closedByOther: self = composed.merged == true ? .merged : .closed
        case .mention: self = .mention
        case nil: self = .summary
        }
    }

    private static func review(_ decision: ReviewState?) -> Self {
        switch decision {
        case .approved: .approved
        case .changesRequested: .changesRequested
        default: .reviewed
        }
    }
}
