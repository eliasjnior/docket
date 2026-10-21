import Foundation

/// Local tags (FR-80–FR-85): normalized, validated, never written to GitHub.
public enum Tags {
    public static let maximumPerPullRequest = 5
    public static let maximumLength = 24

    public enum Rejection: Error, Hashable, Sendable {
        case invalidCharacters
        case tooLong
        case alreadyAdded
        case tooMany
        case empty
    }

    /// Trimmed, lower-cased, spaces and underscores turned into `-` (`docs/04-data.md` §2.1).
    public static func normalize(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "_", with: "-")
    }

    /// The tag to store for `input`, or why it is rejected.
    public static func validate(_ input: String, existing: [String]) -> Result<String, Rejection> {
        let tag = normalize(input)
        if tag.isEmpty { return .failure(.empty) }
        if tag.count > maximumLength { return .failure(.tooLong) }
        if !tag.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) {
            return .failure(.invalidCharacters)
        }
        if existing.contains(tag) { return .failure(.alreadyAdded) }
        if existing.count >= maximumPerPullRequest { return .failure(.tooMany) }
        return .success(tag)
    }

    /// Tags across pull requests, most used first, then alphabetically.
    public static func inUse(_ lists: [[String]]) -> [String] {
        var counts: [String: Int] = [:]
        for tag in lists.joined() { counts[tag, default: 0] += 1 }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    /// At most six suggestions filtered by prefix, `wip` when nothing is in use (FR-83).
    public static func suggestions(inUse: [String], prefix: String, excluding: [String]) -> [String] {
        let typed = normalize(prefix)
        let pool = inUse.isEmpty ? ["wip"] : inUse
        return Array(pool.filter { !excluding.contains($0) && (typed.isEmpty || $0.hasPrefix(typed)) }.prefix(6))
    }
}
