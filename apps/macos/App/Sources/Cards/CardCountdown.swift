import Foundation

/// The time a card has left: it runs while the pointer is off the card and freezes while it is on it, then
/// resumes where it stopped (`docs/05-design.md` §8.1).
struct CardCountdown {
    let lifetime: TimeInterval
    private var elapsed: TimeInterval = 0
    /// When it last started running; `nil` while frozen.
    private var runningSince: Date?

    init(lifetime: TimeInterval, startedAt: Date) {
        self.lifetime = lifetime
        runningSince = startedAt
    }

    mutating func freeze(at now: Date) {
        guard let runningSince else { return }
        elapsed += now.timeIntervalSince(runningSince)
        self.runningSince = nil
    }

    mutating func resume(at now: Date) {
        guard runningSince == nil else { return }
        runningSince = now
    }

    func remaining(at now: Date) -> TimeInterval {
        let running = runningSince.map { now.timeIntervalSince($0) } ?? 0
        return max(0, lifetime - elapsed - running)
    }

    /// From 1, just shown, to 0, gone.
    func fraction(at now: Date) -> Double {
        lifetime > 0 ? remaining(at: now) / lifetime : 0
    }
}
