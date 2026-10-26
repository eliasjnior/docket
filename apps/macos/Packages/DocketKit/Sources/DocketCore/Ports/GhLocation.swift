/// Where Docket installs the GitHub CLI when the Mac has none (FR-15), so the token provider looks there too.
public enum GhLocation {
    public static func managed(home: String) -> String {
        "\(home)/Library/Application Support/Docket/bin/gh"
    }
}
