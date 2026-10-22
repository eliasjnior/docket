import Foundation

/// The script behind *Review with AI* and *Summarize with AI* (spec §9.2).
///
/// Titles and branch names are written by other people, so their text never becomes shell syntax: each value
/// is exported as a single-quoted variable, and each `{placeholder}` in the user's template becomes a reference
/// to it, quoted for where it sits.
public enum CommandScript {
    public static let placeholders = ["url", "repo", "number", "title", "branch"]

    /// A `zsh` script that deletes itself, exports the values, enters `directory` (a fresh temporary folder
    /// when `nil`) and runs the template.
    public static func render(template: String, values: [String: String], directory: String?) -> String {
        var lines = ["#!/bin/zsh", #"rm -f -- "$0""#]
        for name in placeholders {
            lines.append("export \(variable(name))=\(quoted(values[name] ?? ""))")
        }
        if let directory {
            lines.append("cd -- \(quoted(directory)) || exit 1")
        } else {
            lines.append(#"cd -- "$(mktemp -d -t docket)" || exit 1"#)
        }
        lines.append(rewrite(template).text)
        return lines.joined(separator: "\n") + "\n"
    }

    /// Placeholders inside single quotes, which the shell will not expand: Settings warns about them.
    public static func placeholdersInSingleQuotes(_ template: String) -> [String] {
        rewrite(template).literal
    }

    /// `{title}` outside quotes is a word of its own, and a title starting with `-` would read as an option.
    public static func titleStandsAlone(_ template: String) -> Bool {
        rewrite(template).bareTitle
    }

    /// `'…'` with each `'` closed, escaped and reopened.
    static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    static func variable(_ name: String) -> String { "DOCKET_" + name.uppercased() }

    private enum Quote {
        case none
        case single
        case double
    }

    private struct Rewrite {
        var text = ""
        var literal: [String] = []
        var bareTitle = false
    }

    private static func rewrite(_ template: String) -> Rewrite {
        var result = Rewrite()
        var quote = Quote.none
        var characters = Array(template)[...]
        while let character = characters.popFirst() {
            if character == "\\", quote != .single, let next = characters.popFirst() {
                result.text.append(character)
                result.text.append(next)
                continue
            }
            if character == "{", let name = placeholder(at: characters) {
                characters = characters.dropFirst(name.count + 1)
                result.text += reference(name, in: quote)
                if quote == .single { result.literal.append(name) }
                if quote == .none, name == "title" { result.bareTitle = true }
                continue
            }
            quote = next(quote, after: character)
            result.text.append(character)
        }
        return result
    }

    /// A placeholder as it is written where it sits: one quoted word outside quotes, a bare expansion inside
    /// double quotes, and left alone inside single quotes, where nothing expands.
    private static func reference(_ name: String, in quote: Quote) -> String {
        switch quote {
        case .none: "\"${\(variable(name))}\""
        case .double: "${\(variable(name))}"
        case .single: "{\(name)}"
        }
    }

    private static func next(_ quote: Quote, after character: Character) -> Quote {
        switch (character, quote) {
        case ("'", .none): .single
        case ("'", .single): .none
        case ("\"", .none): .double
        case ("\"", .double): .none
        default: quote
        }
    }

    /// The placeholder name when `rest` starts with `name}`.
    private static func placeholder(at rest: ArraySlice<Character>) -> String? {
        placeholders.first { name in
            let candidate = Array(name + "}")
            return rest.count >= candidate.count && Array(rest.prefix(candidate.count)) == candidate
        }
    }
}
