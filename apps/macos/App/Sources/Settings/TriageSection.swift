import DocketCore
import DocketStores
import SwiftUI

/// Settings → Notifications: what Bots and Stale do outside the popover (`docs/02-activity-detection.md` §3.6).
struct TriageSection: View {
    let configStore: ConfigStore
    @State private var extraBots = ""

    var body: some View {
        Section {
            Picker(
                String(localized: "Stale after", comment: "Triage setting"),
                selection: binding(\.triage.staleAfterDays)
            ) {
                ForEach(Config.Triage.allowedStaleDays, id: \.self) { days in
                    Text("\(days) days without human activity", comment: "Stale threshold").tag(days)
                }
            }
            Toggle(
                String(localized: "Count and notify bot pull requests", comment: "Triage setting"),
                isOn: binding(\.triage.countBots))
            Toggle(
                String(localized: "Count and notify stale pull requests", comment: "Triage setting"),
                isOn: binding(\.triage.countStale))
            TextField(
                String(localized: "Also bots", comment: "Extra bot logins field"), text: $extraBots,
                prompt: Text("renovate, ci-user", comment: "Extra bot logins placeholder")
            )
            .onSubmit(saveExtraBots)
            .onAppear { extraBots = configStore.config.triage.extraBotLogins.joined(separator: ", ") }
            .onDisappear(perform: saveExtraBots)
        } header: {
            Text("Bots and stale pull requests", comment: "Notifications settings section")
        } footer: {
            Text(
                "When off, they leave the menu bar count, review-request notifications and reminders.",
                comment: "Triage settings caption"
            )
            .font(.caption).foregroundStyle(Color.textSecondary)
        }
    }

    private func saveExtraBots() {
        let logins = extraBots.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        configStore.update { $0.triage.extraBotLogins = logins }
    }

    private func binding<Value>(_ path: WritableKeyPath<Config, Value>) -> Binding<Value> {
        Binding(
            get: { configStore.config[keyPath: path] },
            set: { value in configStore.update { $0[keyPath: path] = value } })
    }
}
