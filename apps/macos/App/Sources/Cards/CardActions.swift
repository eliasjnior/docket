import Foundation

/// What a card can do; the app supplies it, so the cards stay plain views.
@MainActor
struct CardActions {
    /// A click on the card or its primary button: the pull request, or the popover for a group.
    var open: (NotificationCard) -> Void
    var reviewWithAI: (NotificationCard) -> Void
    var showMore: () -> Void
    var dismiss: (String) -> Void
    var dismissAll: () -> Void
    var canReviewWithAI: (NotificationCard) -> Bool = { _ in false }
}
