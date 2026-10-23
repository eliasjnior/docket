import Foundation

extension Config {
    public struct Notifications: Codable, Hashable, Sendable {
        public static let allowedCardSeconds = [6, 10, 15, 30]

        /// Docket's own card, or a banner from Notification Center (`docs/05-design.md` §8).
        public enum Style: String, Codable, Hashable, Sendable, CaseIterable {
            case card
            case system
        }

        public var style: Style
        public var sound: Bool
        /// Cards about something waiting on you stay until acted on; off, every card leaves by itself, as a
        /// banner does.
        public var keepCardsUntilActedOn: Bool
        /// How long a card stays before it leaves by itself.
        public var cardSeconds: Int
        public var reviewRequested: Bool
        public var reviewSubmitted: Bool
        public var commentAdded: Bool
        public var threadReply: Bool
        public var checksFailed: Bool
        public var closedByOther: Bool
        public var mention: Bool

        public init(
            style: Style = .card, sound: Bool = true, keepCardsUntilActedOn: Bool = false, cardSeconds: Int = 10,
            reviewRequested: Bool = true, reviewSubmitted: Bool = true,
            commentAdded: Bool = true, threadReply: Bool = true, checksFailed: Bool = true, closedByOther: Bool = true,
            mention: Bool = true
        ) {
            self.style = style
            self.sound = sound
            self.keepCardsUntilActedOn = keepCardsUntilActedOn
            self.cardSeconds = cardSeconds
            self.reviewRequested = reviewRequested
            self.reviewSubmitted = reviewSubmitted
            self.commentAdded = commentAdded
            self.threadReply = threadReply
            self.checksFailed = checksFailed
            self.closedByOther = closedByOther
            self.mention = mention
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            style = c.value(.style, default: .card)
            sound = c.value(.sound, default: true)
            keepCardsUntilActedOn = c.value(.keepCardsUntilActedOn, default: false)
            let seconds = c.value(.cardSeconds, default: 10)
            cardSeconds = Self.allowedCardSeconds.contains(seconds) ? seconds : 10
            reviewRequested = c.value(.reviewRequested, default: true)
            reviewSubmitted = c.value(.reviewSubmitted, default: true)
            commentAdded = c.value(.commentAdded, default: true)
            threadReply = c.value(.threadReply, default: true)
            checksFailed = c.value(.checksFailed, default: true)
            closedByOther = c.value(.closedByOther, default: true)
            mention = c.value(.mention, default: true)
        }

        public func isEnabled(_ kind: EventKind) -> Bool {
            switch kind {
            case .reviewRequested: reviewRequested
            case .reviewSubmitted: reviewSubmitted
            case .commentAdded: commentAdded
            case .threadReply: threadReply
            case .checksFailed: checksFailed
            case .closedByOther: closedByOther
            case .mention: mention
            }
        }
    }
}
