import DocketCore
import Foundation

/// Reads the token of the signed-in GitHub CLI (`docs/03-architecture.md` §6, FR-10, FR-11).
public actor GhTokenProvider: TokenProvider {
    public static let knownLocations = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]

    private let runner: CommandRunner
    private let configuredPath: @Sendable () async -> String?
    private let home: String
    private var resolvedPath: String?
    private var cached: String?

    public init(
        runner: CommandRunner = ProcessCommandRunner(), home: String = NSHomeDirectory(),
        configuredPath: @escaping @Sendable () async -> String? = { nil }
    ) {
        self.runner = runner
        self.home = home
        self.configuredPath = configuredPath
    }

    public func token() async throws -> String {
        if let cached { return cached }
        return try await refresh()
    }

    public func refresh() async throws -> String {
        let path = try await locate()
        let result: CommandResult
        do {
            result = try await runner.run(
                path, ["auth", "token", "--hostname", "github.com"], environment: environment(for: path), timeout: 5)
        } catch CommandError.timedOut {
            throw TokenError.timedOut
        } catch {
            resolvedPath = nil
            throw TokenError.ghNotFound
        }
        let token = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == 0, !token.isEmpty, !token.contains("\n") else {
            cached = nil
            throw TokenError.signedOut
        }
        cached = token
        return token
    }

    /// Forgets the cached path, so a changed setting or a fresh install of `gh` is picked up.
    public func reset() {
        resolvedPath = nil
        cached = nil
    }

    /// The `gh` in use, for settings.
    public func location() async -> String? {
        try? await locate()
    }

    private func locate() async throws -> String {
        if let configured = await configuredPath(), !configured.isEmpty {
            guard runner.isExecutable(configured) else { throw TokenError.ghNotFound }
            return configured
        }
        if let resolvedPath { return resolvedPath }
        // Homebrew's `gh` first: once installed it outranks the copy Docket installed for itself.
        if let known = (Self.knownLocations + [GhLocation.managed(home: home)]).first(where: runner.isExecutable) {
            resolvedPath = known
            return known
        }
        let result = try? await runner.run(
            "/bin/zsh", ["-lc", "command -v gh"], environment: ["HOME": home, "PATH": "/usr/bin:/bin"], timeout: 3)
        let found = result?.output.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard result?.status == 0, found.hasPrefix("/"), runner.isExecutable(found) else {
            throw TokenError.ghNotFound
        }
        resolvedPath = found
        return found
    }

    /// `HOME` and a `PATH` only, so a stray `GH_TOKEN` cannot override the signed-in account.
    private func environment(for path: String) -> [String: String] {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        return ["HOME": home, "PATH": "\(directory):/usr/bin:/bin"]
    }
}
