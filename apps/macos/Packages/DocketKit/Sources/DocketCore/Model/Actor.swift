import Foundation

/// The author of a pull request, review, comment or event.
public struct Actor: Codable, Hashable, Sendable {
    public var login: String
    /// `__typename == "Bot"`. A login ending in `[bot]` is a bot too (`docs/02-activity-detection.md` §5.4).
    public var isBot: Bool

    public init(login: String, isBot: Bool = false) {
        self.login = login
        self.isBot = isBot
    }

    public var isAnyBot: Bool { isBot || login.hasSuffix("[bot]") }
}
