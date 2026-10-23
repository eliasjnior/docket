import Foundation

/// A link found in a pull request's description or in a bot's comment, such as a preview deploy, for the row's
/// `PR Links` menu (`docs/05-design.md` §6.5). The text around it is never kept.
public struct PullRequestLink: Codable, Hashable, Sendable {
    public var url: URL
    /// The link's own text, `[Visit Preview](…)`, when it has one.
    public var title: String?
    /// The bot whose comment held it; `nil` for the description.
    public var source: String?

    public init(url: URL, title: String? = nil, source: String? = nil) {
        self.url = url
        self.title = title
        self.source = source
    }
}
