import Foundation

/// Time for the stores, injected so tests drive polls without waiting (`docs/06-engineering-practices.md` §10.4).
public protocol Clock: Sendable {
    func now() -> Date
    func sleep(for interval: TimeInterval) async throws
}

public struct SystemClock: Clock {
    public init() {}

    public func now() -> Date { Date() }

    public func sleep(for interval: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(max(0, interval)))
    }
}
