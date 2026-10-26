import DocketActivity

/// The `gh` commands of the sign-in and scope steps, as a script that deletes itself like *Review with AI*'s.
public enum SetupCommand {
    public static let signIn = [
        "auth", "login", "--hostname", "github.com", "--git-protocol", "https", "--web", "--scopes", "read:org",
    ]

    public static func grant(_ scopes: [String]) -> [String] {
        ["auth", "refresh", "--hostname", "github.com", "--scopes", scopes.joined(separator: ",")]
    }

    public static func script(gh: String, arguments: [String]) -> String {
        let command = ([gh] + arguments).map(CommandScript.quoted).joined(separator: " ")
        return ["#!/bin/zsh", #"rm -f -- "$0""#, command].joined(separator: "\n") + "\n"
    }
}
