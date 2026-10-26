import AppKit
import DocketActivity
import DocketCore
import os

/// Runs *Review with AI*, *Summarize with AI* (spec §9.2, D-28) and the setup's `gh` steps in the user's
/// terminal. Docket writes a
/// script that deletes itself and asks the terminal to open it; the user's command does the rest. The token is
/// never in the script, its environment or its arguments.
@MainActor
enum TerminalLauncher {
    enum Action {
        case review
        case summarize
    }

    private static let log = Logger(subsystem: "com.eliasjnior.docket", category: "terminal")

    static func run(_ action: Action, for pullRequest: PullRequest, integrations: Config.Integrations) {
        let template = action == .review ? integrations.reviewCommand : integrations.summarizeCommand
        let script = CommandScript.render(
            template: template,
            values: [
                "url": pullRequest.url.absoluteString, "repo": pullRequest.repository,
                "number": "\(pullRequest.number)", "title": pullRequest.title, "branch": pullRequest.headRefName ?? "",
            ],
            directory: integrations.clone(of: pullRequest.repository))
        open(script: script, terminalApp: integrations.terminalApp)
    }

    /// Writes `script` to a private `.command` file, which deletes itself, and opens it in the chosen terminal.
    static func open(script: String, terminalApp: String?) {
        do {
            let folder = FileManager.default.temporaryDirectory.appending(path: "Docket", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let file = folder.appending(path: "\(UUID().uuidString).command")
            try Data(script.utf8).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            if let path = terminalApp, FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.open(
                    [file], withApplicationAt: URL(fileURLWithPath: path),
                    configuration: NSWorkspace.OpenConfiguration()
                ) { _, error in
                    if let error { log.error("Terminal did not open: \(error.localizedDescription, privacy: .public)") }
                }
            } else {
                NSWorkspace.shared.open(file)
            }
        } catch {
            log.error("Could not write the command script: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Terminals Docket offers by name, when installed; anything else is `Choose…`.
    static let knownTerminals: [(name: String, bundleID: String)] = [
        ("Terminal", "com.apple.Terminal"), ("iTerm", "com.googlecode.iterm2"), ("Ghostty", "com.mitchellh.ghostty"),
        ("Warp", "dev.warp.Warp-Stable"), ("WezTerm", "com.github.wez.wezterm"),
    ]

    static var installedTerminals: [(name: String, path: String)] {
        knownTerminals.compactMap { entry in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID).map { (entry.name, $0.path) }
        }
    }
}
