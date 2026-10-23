import Foundation

/// One notification as Docket's own card shows it (`docs/05-design.md` §8.1), built from the worded
/// notification in `Environment/`, so the cards never see an adapter.
struct NotificationCard: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case reviewRequested
        case approved
        case changesRequested
        case reviewed
        case comment
        case reply
        case checksFailed
        case merged
        case closed
        case mention
        case reminder
        /// Several events, the overflow line or the Focus digest.
        case summary
    }

    var id: String
    var kind: Kind
    /// `@ana is waiting for your review`.
    var headline: String
    /// The pull request's title, for a card about one pull request.
    var title: String?
    /// `acme/api #482 · via @acme/backend`, or a group's lines.
    var detail: String
    var repository: String?
    var url: URL?
    var pullRequestID: String?
    /// Stays until it is acted on or dismissed; the others leave after `lifetime` seconds.
    var isSticky: Bool
    var lifetime: TimeInterval = 10
}
