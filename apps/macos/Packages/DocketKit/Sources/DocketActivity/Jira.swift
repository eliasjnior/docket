import DocketCore
import Foundation

/// *Open in Jira* (spec §9.1). The description almost always links the issue, so that link wins. Without one, a
/// key in the title or the branch is opened on the Jira site the other pull requests link to.
public enum Jira {
    public static func link(for pullRequest: PullRequest, among others: [PullRequest]) -> URL? {
        if let link = pullRequest.issueLinks.first { return link }
        guard let site = site(of: others) else { return nil }
        let key =
            self.key(in: pullRequest.title)
            ?? pullRequest.headRefName.flatMap { self.key(in: $0, caseInsensitive: true) }
        return key.flatMap { URL(string: "\(site)/browse/\($0)") }
    }

    /// The Jira site most of the listed pull requests link to, as `https://host`.
    static func site(of pullRequests: [PullRequest]) -> String? {
        let hosts = pullRequests.flatMap(\.issueLinks).compactMap { link -> String? in
            guard let host = link.host?.lowercased() else { return nil }
            return "\(link.scheme ?? "https")://\(host)"
        }
        let counts = Dictionary(grouping: hosts, by: { $0 }).mapValues(\.count)
        return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
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
        let key = text[span].uppercased()
        return notIssues.contains(String(key.prefix { $0 != "-" })) ? nil : key
    }

    /// Prefixes of names that look like issue keys and are not: `UTF-8`, `SHA-256`, `ISO-8601`.
    static let notIssues: Set<String> = [
        "UTF", "SHA", "ISO", "HTTP", "HTTPS", "TLS", "SSL", "RFC", "MD", "IPV", "ES", "PEP", "CVE", "GPT", "H", "X",
    ]
}
