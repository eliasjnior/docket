import Foundation

/// The latest thing one actor did on a pull request, judged human or bot when read, not when stored.
public struct ActivityStamp: Codable, Hashable, Sendable {
    public var login: String
    public var isBot: Bool
    public var at: Date

    public init(login: String, isBot: Bool = false, at: Date) {
        self.login = login
        self.isBot = isBot
        self.at = at
    }
}

/// The head commit's author and date. A bot's commit may have no GitHub user; its git name, read only to
/// set `isBot`, is never kept (`docs/04-data.md` §5).
public struct CommitStamp: Codable, Hashable, Sendable {
    public var login: String?
    public var isBot: Bool
    public var at: Date

    public init(login: String?, isBot: Bool = false, at: Date) {
        self.login = login
        self.isBot = isBot
        self.at = at
    }
}

/// A GitHub label, read only (non-negotiable 5).
public struct Label: Codable, Hashable, Sendable {
    public var name: String
    /// Six hex digits, without `#`.
    public var color: String

    public init(name: String, color: String) {
        self.name = name
        self.color = color
    }
}
