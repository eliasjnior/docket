import DocketCore
import Foundation

/// The links in a description or a comment: Markdown and HTML links with their text, then bare URLs. Images,
/// badges and avatars are left out, and so is anything on GitHub's attachment hosts.
enum Links {
    static let limit = 10

    /// A link where it was found in the text.
    private struct Found {
        var at: Int
        var url: String
        var title: String?
    }
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "svg", "webp"]
    static let ignoredHosts: Set<String> = [
        "img.shields.io", "avatars.githubusercontent.com", "user-images.githubusercontent.com",
        "private-user-images.githubusercontent.com", "camo.githubusercontent.com", "badgen.net",
    ]

    /// In the order they appear; a URL that also has text somewhere keeps the text.
    static func extract(from body: String?, source: String? = nil) -> [PullRequestLink] {
        guard let body, !body.isEmpty else { return [] }
        var found: [Found] = []
        for match in matches(#"(!?)\[([^\]]*)\]\((https?://[^\s)]+)\)"#, in: body) where match.groups[1].isEmpty {
            found.append(Found(at: match.at, url: match.groups[3], title: match.groups[2]))
        }
        for match in matches(#"<a\s[^>]*href="(https?://[^"]+)"[^>]*>(.*?)</a>"#, in: body) {
            found.append(Found(at: match.at, url: match.groups[1], title: match.groups[2]))
        }
        for match in matches(#"https?://[^\s<>"'()\[\]]+"#, in: body) {
            found.append(Found(at: match.at, url: match.groups[0], title: nil))
        }
        var titles: [String: String] = [:]
        for item in found {
            let url = trimmed(item.url)
            if titles[url] == nil, let title = cleaned(item.title, url: url) { titles[url] = title }
        }
        var seen = Set<String>()
        var links: [PullRequestLink] = []
        for item in found.sorted(by: { $0.at < $1.at }) {
            let text = trimmed(item.url)
            guard links.count < limit, let url = URL(string: text), keeps(url), seen.insert(text).inserted else {
                continue
            }
            links.append(PullRequestLink(url: url, title: titles[text], source: source))
        }
        return links
    }

    private static func trimmed(_ url: String) -> String {
        url.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
    }

    private static func keeps(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), !ignoredHosts.contains(host) else { return false }
        if host == "github.com", url.path.hasPrefix("/user-attachments") { return false }
        return !imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// The link's text without Markdown emphasis or HTML tags; `nil` when it is empty or the URL itself.
    private static func cleaned(_ title: String?, url: String) -> String? {
        guard var title else { return nil }
        title = title.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        title = title.replacingOccurrences(of: #"[*_`]"#, with: "", options: .regularExpression)
        title = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !title.isEmpty, title != url else { return nil }
        return String(title.prefix(60))
    }

    /// Each match's position and capture groups, the whole match first; a group that did not take part is empty.
    private static func matches(_ pattern: String, in text: String) -> [(at: Int, groups: [String])] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            let groups = (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
            return (match.range.location, groups)
        }
    }
}
