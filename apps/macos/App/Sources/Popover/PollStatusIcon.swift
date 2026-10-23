import DocketStores
import SwiftUI

/// Why the list may be out of date — a failed poll, offline, GitHub's rate limit, or older than two poll
/// intervals — as a symbol beside refresh, with the sentence on hover (`docs/05-design.md` §7.2). A banner for
/// it pushed the whole list down each time.
struct PollStatusIcon: View {
    let watch: WatchStore
    let now: Date
    let retry: () -> Void

    var body: some View {
        if let status {
            Button(action: status.retries ? retry : {}) {
                Image(systemName: status.symbol).foregroundStyle(status.color)
            }
            .buttonStyle(.borderless)
            .help(status.text)
            .accessibilityLabel(Text(verbatim: status.text))
        }
    }

    /// The reason in a sentence a person can act on.
    static func explain(_ reason: PollFailure) -> String {
        switch reason {
        case .network:
            String(
                localized: "GitHub could not be reached; the connection dropped or timed out.",
                comment: "Failed poll reason")
        case .server(let status) where (500...599).contains(status):
            String(
                localized: "GitHub had a server error (HTTP \(status)), usually brief.", comment: "Failed poll reason")
        case .server(let status):
            String(localized: "GitHub refused the request (HTTP \(status)).", comment: "Failed poll reason")
        case .invalidResponse:
            String(localized: "GitHub sent an answer Docket could not read.", comment: "Failed poll reason")
        case .other(let description):
            String(localized: "\(description).", comment: "Failed poll reason: an unexpected error, as reported")
        }
    }

    private struct Status {
        var symbol: String
        var color: Color
        var text: String
        var retries = false
    }

    private var status: Status? {
        switch watch.problem {
        case .rateLimited(let until):
            return Status(
                symbol: "clock", color: .textSecondary,
                text: String(
                    localized: "Paused by GitHub's rate limit until \(Banners.time(until, now: now)).",
                    comment: "Rate-limit banner"))
        case .offline:
            return Status(
                symbol: "wifi.slash", color: .textSecondary,
                text: watch.fetchedAt.map {
                    String(
                        localized: "Offline. Showing data from \(Banners.time($0, now: now)).",
                        comment: "Offline banner")
                } ?? String(localized: "Offline.", comment: "Offline banner without data"))
        case .failed(let at, let reason):
            let why = Self.explain(reason)
            let when = Banners.time(at, now: now)
            return Status(
                symbol: "exclamationmark.triangle.fill", color: .statusAttention,
                text: String(
                    localized: "Couldn't update: \(why) Showing data from \(when). Click to try again.",
                    comment: "Failed poll, on hover: the reason, then when the data shown is from"),
                retries: true)
        case nil:
            // The list is older than two poll intervals (FR-44).
            guard !watch.isPolling, watch.isStale(now: now), let fetchedAt = watch.fetchedAt else { return nil }
            return Status(
                symbol: "clock.arrow.circlepath", color: .textSecondary,
                text: String(
                    localized: "Updated \(max(1, Int(now.timeIntervalSince(fetchedAt) / 60))) min ago",
                    comment: "Banner when the list is older than two poll intervals"))
        }
    }
}
