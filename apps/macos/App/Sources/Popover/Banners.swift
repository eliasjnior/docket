import AppKit
import DocketStores
import SwiftUI

/// One-line banners between the header and the sections, in the order of `docs/05-design.md` §7.2.
struct Banners: View {
    let watch: WatchStore
    let actions: PopoverActions
    let now: Date

    var body: some View {
        VStack(spacing: 0) {
            ForEach(watch.snapshot.samlOrganizations) { organization in
                BannerRow(
                    symbol: "lock.shield", color: .statusAttention,
                    text: String(
                        localized: "\(organization.login) requires SAML authorization.", comment: "SAML banner"),
                    action: String(localized: "Authorize", comment: "SAML banner button")
                ) { actions.row.open(organization.url) }
            }
            switch watch.problem {
            case .rateLimited(let until):
                BannerRow(
                    symbol: "clock", color: .textSecondary,
                    text: String(
                        localized: "Paused by GitHub's rate limit until \(Self.time(until, now: now)).",
                        comment: "Rate-limit banner"))
            case .offline:
                BannerRow(
                    symbol: "wifi.slash", color: .textSecondary,
                    text: watch.fetchedAt.map {
                        String(
                            localized: "Offline. Showing data from \(Self.time($0, now: now)).",
                            comment: "Offline banner")
                    } ?? String(localized: "Offline.", comment: "Offline banner without data"))
            case .failed(let at):
                BannerRow(
                    symbol: "exclamationmark.triangle", color: .statusAttention,
                    text: String(
                        localized: "Couldn't update. Showing data from \(Self.time(at, now: now)).",
                        comment: "Failed poll banner"),
                    action: String(localized: "Try Again", comment: "Failed poll banner button"),
                    perform: actions.refresh)
            case nil:
                EmptyView()
            }
            if watch.snapshot.state.baselineAt != nil, !watch.snapshot.state.baselineNoticeDismissed,
                watch.account == .ready
            {
                BannerRow(
                    symbol: "info.circle", color: .textSecondary,
                    text: String(
                        localized: "Watching from now on. What was already waiting is listed but did not notify.",
                        comment: "First-run banner"),
                    action: String(localized: "OK", comment: "First-run banner button"),
                    perform: actions.dismissBaselineNotice)
            }
        }
    }

    /// `HH:mm` in the user's locale, with the date when not today.
    static func time(_ date: Date, now: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct BannerRow: View {
    let symbol: String
    let color: Color
    let text: String
    var action: String?
    var perform: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(verbatim: text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let action, let perform {
                Button(action, action: perform).controlSize(.small)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
