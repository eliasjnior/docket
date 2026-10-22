import DocketCore
import Foundation

/// *Open in Jira* (spec §9.1): a link in the body on the base's host, else a key in the title, else in the branch.
public enum Jira {
    public static func link(for pullRequest: PullRequest, base: String?) -> URL? {
        guard let base = normalized(base), let host = URL(string: base)?.host?.lowercased() else { return nil }
        if let link = pullRequest.issueLinks.first(where: { $0.host?.lowercased() == host }) { return link }
        let key =
            self.key(in: pullRequest.title)
            ?? pullRequest.headRefName.flatMap { self.key(in: $0, caseInsensitive: true) }
        return key.flatMap { URL(string: "\(base)/browse/\($0)") }
    }

    /// The first `ABC-123`. A branch is often lower case (`abc-123-fix`), so it may be read case-insensitively;
    /// a title is not, so `Bump node-18` is not taken for an issue.
    public static func key(in text: String, caseInsensitive: Bool = false) -> String? {
        let letters = caseInsensitive ? "A-Za-z" : "A-Z"
        let pattern = "(?<![A-Za-z0-9])([\(letters)][\(letters)0-9]+-\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), let span = Range(match.range(at: 1), in: text)
        else { return nil }
        return text[span].uppercased()
    }

    /// `acme.atlassian.net` or `https://acme.atlassian.net/` as `https://acme.atlassian.net`.
    static func normalized(_ base: String?) -> String? {
        guard var text = base?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }
}
