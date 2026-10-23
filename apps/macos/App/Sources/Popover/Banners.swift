import AppKit
import DocketStores
import SwiftUI

/// One-line banners between the header and the sections, in the order of `docs/05-design.md` §7.2.
struct Banners: View {
    let watch: WatchStore
    let permission: NotificationPermission
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
            if watch.snapshot.state.baselineAt != nil, watch.config.launchAtLogin == nil {
                HStack(spacing: 8) {
                    Image(systemName: "power").foregroundStyle(Color.textSecondary)
                    Text("Open Docket at login?", comment: "Launch at login banner")
                    Spacer(minLength: 4)
                    Button(String(localized: "Not Now", comment: "Launch at login banner button")) {
                        actions.launchAtLogin(false)
                    }
                    .controlSize(.small)
                    Button(String(localized: "Turn On", comment: "Launch at login banner button")) {
                        actions.launchAtLogin(true)
                    }
                    .controlSize(.small)
                }
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            if watch.snapshot.state.focusHold != nil {
                BannerRow(
                    symbol: "moon", color: .textSecondary,
                    text: String(
                        localized: "Holding \(watch.snapshot.state.held.count) updates until your Focus ends.",
                        comment: "Focus hold banner"),
                    action: String(localized: "Deliver Now", comment: "Focus hold banner button"),
                    perform: actions.deliverHeld)
            }
            if permission.status == .denied, watch.config.notifications.style == .system {
                BannerRow(
                    symbol: "bell.slash", color: .textSecondary,
                    text: String(localized: "Notifications are off for Docket.", comment: "Permission banner"),
                    action: String(localized: "Open System Settings", comment: "Permission banner button"),
                    perform: NotificationSettingsLink.open)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
