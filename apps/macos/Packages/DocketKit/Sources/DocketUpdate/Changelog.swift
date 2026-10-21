import Foundation

public struct ChangelogEntry: Equatable, Sendable, Identifiable {
    public let version: SemanticVersion
    public let date: String?
    public let sections: [Section]

    public var id: SemanticVersion { version }

    public struct Section: Equatable, Sendable {
        public let title: String
        public let items: [String]
    }
}

/// Parses the release-please changelog into entries that read well in the app.
public enum Changelog {
    public static func parse(_ markdown: String) -> [ChangelogEntry] {
        var entries: [ChangelogEntry] = []
        var version: SemanticVersion?
        var date: String?
        var sections: [ChangelogEntry.Section] = []
        var sectionTitle: String?
        var items: [String] = []

        func closeSection() {
            if let title = sectionTitle, !items.isEmpty {
                sections.append(.init(title: title, items: items))
            }
            sectionTitle = nil
            items = []
        }
        func closeEntry() {
            closeSection()
            if let version { entries.append(.init(version: version, date: date, sections: sections)) }
            sections = []
        }

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                closeEntry()
                (version, date) = parseHeading(String(line.dropFirst(3)))
            } else if line.hasPrefix("### ") {
                closeSection()
                sectionTitle = String(line.dropFirst(4))
            } else if line.hasPrefix("* ") || line.hasPrefix("- "), sectionTitle != nil {
                items.append(clean(String(line.dropFirst(2))))
            }
        }
        closeEntry()
        return entries.sorted { $0.version > $1.version }
    }

    /// Entries newer than `lastSeen`, up to and including `current`.
    public static func entries(_ all: [ChangelogEntry], after lastSeen: SemanticVersion?, upTo current: SemanticVersion)
        -> [ChangelogEntry]
    {
        all.filter { entry in entry.version <= current && lastSeen.map { entry.version > $0 } ?? true }
    }

    static func parseHeading(_ heading: String) -> (SemanticVersion?, String?) {
        let versionText = heading.split(separator: " ").first.map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        }
        let cleanedVersion = versionText.map { $0.components(separatedBy: "](").first ?? $0 }
        let date = heading.range(of: #"\((\d{4}-\d{2}-\d{2})\)"#, options: .regularExpression).map {
            String(heading[$0]).trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        }
        return (cleanedVersion.flatMap(SemanticVersion.init), date)
    }

    /// Drops scope markers and trailing PR / commit links: `**macos:** add x ([#1](…)) ([abc](…))` → `Add x`.
    static func clean(_ item: String) -> String {
        var text = item.replacingOccurrences(of: #"^\*\*[^*]+:\*\*\s*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(
            of: #"(\s*\(\[[^\]]+\]\([^)]+\)\))+\s*$"#, with: "", options: .regularExpression)
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
