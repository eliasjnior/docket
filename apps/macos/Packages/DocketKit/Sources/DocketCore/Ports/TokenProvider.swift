import Foundation

/// The token of the signed-in GitHub CLI, held only in memory (D-02).
public protocol TokenProvider: Sendable {
    /// The cached token, read from `gh` on first use.
    func token() async throws -> String
    /// Reads the token from `gh` again, for a `401` or the hourly check (`docs/03-architecture.md` §6).
    func refresh() async throws -> String
}

public enum TokenError: Error, Hashable, Sendable {
    case ghNotFound
    case signedOut
    case timedOut
}
