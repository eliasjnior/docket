import DocketCore
import DocketStores
import SwiftUI

/// Settings → Notifications (`docs/05-design.md` §9): permission, one switch per kind, the bot allowlist.
struct NotificationsSettingsView: View {
    let configStore: ConfigStore
    let permission: NotificationPermission
    let requestPermission: () -> Void
    @State private var newBot = ""
    @State private var selectedBot: String?

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Permission", comment: "Notifications setting")) {
                    switch permission.status {
                    case .allowed:
                        Text("Allowed", comment: "Notification permission state")
                    case .notAsked:
                        HStack {
                            Text("Not asked", comment: "Notification permission state")
                            Button(
                                String(localized: "Allow…", comment: "Notification permission button"),
                                action: requestPermission)
                        }
                    case .denied:
                        HStack {
                            Text("Off in System Settings", comment: "Notification permission state")
                            Button(String(localized: "Open System Settings", comment: "Notification permission button"))
                            {
                                NotificationSettingsLink.open()
                            }
                        }
                    }
                }
            }
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
            }
            Section {
                List(selection: $selectedBot) {
                    ForEach(configStore.config.botAllowlist, id: \.self) { Text(verbatim: $0).tag($0) }
                }
                .frame(minHeight: 60)
                HStack {
                    TextField(String(localized: "Bot login", comment: "Bot allowlist field"), text: $newBot)
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

    private func binding(_ path: WritableKeyPath<Config, Bool>) -> Binding<Bool> {
        Binding(
            get: { configStore.config[keyPath: path] },
            set: { value in configStore.update { $0[keyPath: path] = value } })
    }
}
