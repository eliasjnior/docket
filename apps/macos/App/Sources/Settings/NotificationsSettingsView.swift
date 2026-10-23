import AppKit
import DocketActivity
import DocketCore
import DocketStores
import SwiftUI

/// Settings → Notifications (`docs/05-design.md` §9): permission, one switch per kind, the bot allowlist.
struct NotificationsSettingsView: View {
    let configStore: ConfigStore
    let permission: NotificationPermission
    let requestPermission: () -> Void
    var showExampleCards: () -> Void = {}
    var holdSince: Date?
    @State private var newBot = ""
    @State private var selectedBot: String?

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Show as", comment: "Notification style setting"), selection: style) {
                    Text("Docket cards", comment: "Notification style").tag(Config.Notifications.Style.card)
                    Text("macOS notifications", comment: "Notification style").tag(Config.Notifications.Style.system)
                }
                Toggle(
                    String(localized: "Play a sound", comment: "Notification setting"),
                    isOn: binding(\.notifications.sound)
                )
                .disabled(configStore.config.notifications.style != .card)
                Toggle(
                    String(
                        localized: "Keep review requests and mentions until I act on them",
                        comment: "Notification setting"),
                    isOn: binding(\.notifications.keepCardsUntilActedOn)
                )
                .disabled(configStore.config.notifications.style != .card)
                Picker(
                    String(localized: "Cards stay for", comment: "Card lifetime picker"),
                    selection: Binding(
                        get: { configStore.config.notifications.cardSeconds },
                        set: { value in configStore.update { $0.notifications.cardSeconds = value } })
                ) {
                    ForEach(Config.Notifications.allowedCardSeconds, id: \.self) { seconds in
                        Text("\(seconds) seconds", comment: "Card lifetime").tag(seconds)
                    }
                }
                .disabled(configStore.config.notifications.style != .card)
                HStack {
                    Text(
                        "Cards leave after a few seconds, like a banner; the pointer on a card holds it.",
                        comment: "Notification style caption"
                    )
                    .font(.caption).foregroundStyle(Color.textSecondary)
                    Spacer()
                    Button(
                        String(localized: "Show Example", comment: "Notification style button"),
                        action: showExampleCards
                    )
                    .disabled(configStore.config.notifications.style != .card)
                }
            }
            if configStore.config.notifications.style == .system {
                permissionSection
            }
            notifyAbout
            RemindersSection(configStore: configStore)
            TriageSection(configStore: configStore)
            Section(String(localized: "Focus", comment: "Notifications settings section")) {
                HStack {
                    Text("To hold notifications during a Focus, add Docket's filter to it.", comment: "Focus setting")
                    Spacer()
                    Button(String(localized: "Open Focus Settings", comment: "Focus setting button")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                Text(verbatim: holdState).foregroundStyle(Color.textSecondary)
            }
            Section {
                List(selection: $selectedBot) {
                    ForEach(configStore.config.botAllowlist, id: \.self) { Text(verbatim: $0).tag($0) }
                }
                .frame(minHeight: 60)
                HStack {
                    TextField(
                        String(localized: "Bot login", comment: "Bot allowlist field"), text: $newBot,
                        prompt: Text("copilot-pull-request-reviewer", comment: "Bot allowlist placeholder")
                    )
                    .labelsHidden()
                    .onSubmit(addBot)
                    Button(action: addBot) { Image(systemName: "plus") }
                        .accessibilityLabel(Text("Add bot", comment: "Bot allowlist button"))
                    Button {
                        guard let selectedBot else { return }
                        configStore.update { $0.botAllowlist.removeAll { $0 == selectedBot } }
                        self.selectedBot = nil
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedBot == nil)
                    .accessibilityLabel(Text("Remove bot", comment: "Bot allowlist button"))
                }
            } header: {
                Text("Bots", comment: "Notifications settings section")
            } footer: {
                Text("Bots never notify unless they are listed here.", comment: "Bot allowlist caption")
                    .font(.caption).foregroundStyle(Color.textSecondary)
            }
        }
        .formStyle(.grouped)
    }

    private var permissionSection: some View {
        Section {
            LabeledContent(String(localized: "Permission", comment: "Notifications setting")) {
                switch permission.status {
                case .allowed:
                    Text("Allowed", comment: "Notification permission state")
                case .notAsked:
                    HStack {
                        Text("Not asked", comment: "Notification permission state")
                        Button(
                            String(localized: "Allow", comment: "Notification permission button"),
                            action: requestPermission)
                    }
                case .denied:
                    HStack {
                        Text("Off in System Settings", comment: "Notification permission state")
                        Button(String(localized: "Open System Settings", comment: "Notification permission button")) {
                            NotificationSettingsLink.open()
                        }
                    }
                }
            }
        }
    }

    private var notifyAbout: some View {
        Section(String(localized: "Notify me about", comment: "Notifications settings section")) {
            Toggle(
                String(localized: "Review requested", comment: "Notification kind"),
                isOn: binding(\.notifications.reviewRequested))
            Toggle(
                String(localized: "Review on your pull request", comment: "Notification kind"),
                isOn: binding(\.notifications.reviewSubmitted))
            Toggle(
                String(localized: "Comment on your pull request", comment: "Notification kind"),
                isOn: binding(\.notifications.commentAdded))
            Toggle(
                String(localized: "Reply to your comment", comment: "Notification kind"),
                isOn: binding(\.notifications.threadReply))
            Toggle(
                String(localized: "Checks failing on your pull request", comment: "Notification kind"),
                isOn: binding(\.notifications.checksFailed))
            Toggle(
                String(
                    localized: "Your pull request merged or closed by someone else", comment: "Notification kind"),
                isOn: binding(\.notifications.closedByOther))
            Toggle(
                String(localized: "Mention of you", comment: "Notification kind"),
                isOn: binding(\.notifications.mention))
        }
    }

    private var holdState: String {
        guard let holdSince else { return String(localized: "Not holding", comment: "Focus hold state") }
        return String(
            localized: "Holding since \(holdSince.formatted(date: .omitted, time: .shortened))",
            comment: "Focus hold state")
    }

    private func addBot() {
        let login = newBot.trimmingCharacters(in: .whitespaces)
        guard !login.isEmpty else { return }
        configStore.update { config in
            if !config.botAllowlist.contains(where: { $0.caseInsensitiveCompare(login) == .orderedSame }) {
                config.botAllowlist.append(login)
            }
        }
        newBot = ""
    }

    private var style: Binding<Config.Notifications.Style> {
        Binding(
            get: { configStore.config.notifications.style },
            set: { value in configStore.update { $0.notifications.style = value } })
    }

    private func binding(_ path: WritableKeyPath<Config, Bool>) -> Binding<Bool> {
        Binding(
            get: { configStore.config[keyPath: path] },
            set: { value in configStore.update { $0[keyPath: path] = value } })
    }
}

/// The Reminders group (FR-66, FR-67): disabled, not hidden, while reminders are off.
struct RemindersSection: View {
    let configStore: ConfigStore

    var body: some View {
        let reminders = configStore.config.reminders
        Section {
            Toggle(
                String(localized: "Remind me about pending reviews", comment: "Reminders setting"),
                isOn: binding(\.enabled))
            Picker(String(localized: "Every", comment: "Reminder interval"), selection: binding(\.intervalMinutes)) {
                Text("15 minutes", comment: "Reminder interval").tag(15)
                Text("30 minutes", comment: "Reminder interval").tag(30)
                Text("1 hour", comment: "Reminder interval").tag(60)
                Text("2 hours", comment: "Reminder interval").tag(120)
                Text("4 hours", comment: "Reminder interval").tag(240)
                Text("8 hours", comment: "Reminder interval").tag(480)
            }
            .disabled(!reminders.enabled)
            Toggle(String(localized: "Quiet hours", comment: "Reminders setting"), isOn: binding(\.quietHours.enabled))
                .disabled(!reminders.enabled)
            HStack {
                DatePicker(
                    String(localized: "From", comment: "Quiet hours start"), selection: time(\.quietHours.start),
                    displayedComponents: .hourAndMinute)
                DatePicker(
                    String(localized: "To", comment: "Quiet hours end"), selection: time(\.quietHours.end),
                    displayedComponents: .hourAndMinute)
            }
            .disabled(!reminders.enabled || !reminders.quietHours.enabled)
        } header: {
            Text("Reminders", comment: "Notifications settings section")
        } footer: {
            Text("Reminders pause in this window. Other notifications follow Focus.", comment: "Quiet hours caption")
                .font(.caption).foregroundStyle(Color.textSecondary)
        }
    }

    private func binding<Value>(_ path: WritableKeyPath<Config.Reminders, Value>) -> Binding<Value> {
        Binding(
            get: { configStore.config.reminders[keyPath: path] },
            set: { value in configStore.update { $0.reminders[keyPath: path] = value } })
    }

    /// `HH:mm` shown as a time picker; a start equal to the end is refused (`docs/02-activity-detection.md` §5.7).
    private func time(_ path: WritableKeyPath<Config.Reminders, String>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = Reminders.minutes(configStore.config.reminders[keyPath: path]) ?? 0
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date())
                    ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                let text = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
                configStore.update { config in
                    var next = config.reminders
                    next[keyPath: path] = text
                    if next.quietHours.start != next.quietHours.end { config.reminders = next }
                }
            })
    }
}
