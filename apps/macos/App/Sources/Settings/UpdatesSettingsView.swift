import DocketCore
import DocketStores
import DocketUpdate
import SwiftUI

/// Settings → Updates, as in Lookout: automatic checks and install, `Check Now`, last checked.
struct UpdatesSettingsView: View {
    let configStore: ConfigStore
    let updates: UpdateStore
    let info: AppInfo
    let showWhatsNew: () -> Void
    let showPrompt: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent(
                    String(localized: "Current version", comment: "Updates setting"), value: info.displayVersion)
                LabeledContent(String(localized: "Status", comment: "Updates setting")) { status }
                if let lastChecked = updates.lastChecked {
                    LabeledContent(String(localized: "Last checked", comment: "Updates setting")) {
                        Text(lastChecked, format: .relative(presentation: .named))
                    }
                }
                HStack {
                    Button(String(localized: "Check Now", comment: "Updates button")) {
                        Task {
                            await updates.check(userInitiated: true)
                            if updates.availableUpdate != nil { showPrompt() }
                        }
                    }
                    .disabled(updates.phase == .checking)
                    Button(String(localized: "What's New", comment: "Updates button"), action: showWhatsNew)
                }
            }
            Section(String(localized: "Automatic updates", comment: "Updates settings section")) {
                Toggle(
                    String(localized: "Check for updates automatically", comment: "Updates setting"),
                    isOn: binding(\.automaticChecks))
                Toggle(
                    String(localized: "Install updates automatically", comment: "Updates setting"),
                    isOn: binding(\.automaticInstall)
                )
                .disabled(!configStore.config.updates.automaticChecks)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var status: some View {
        switch updates.phase {
        case .idle: Text("Not checked yet", comment: "Update status").foregroundStyle(.secondary)
        case .checking: ProgressView().controlSize(.small)
        case .upToDate:
            Label(String(localized: "Up to date", comment: "Update status"), systemImage: "checkmark.circle")
        case .available(let update):
            Button(
                String(localized: "Version \(update.version.description) available", comment: "Update status"),
                action: showPrompt)
        case .installing: Text("Installing", comment: "Update status")
        case .failed(let message):
            Text(verbatim: message).foregroundStyle(Color.statusAttention).multilineTextAlignment(.trailing)
        }
    }

    private func binding(_ path: WritableKeyPath<Config.Updates, Bool>) -> Binding<Bool> {
        Binding(
            get: { configStore.config.updates[keyPath: path] },
            set: { value in configStore.update { $0.updates[keyPath: path] = value } })
    }
}

struct AboutSettingsView: View {
    let info: AppInfo
    let dataFolder: URL
    let showWhatsNew: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            AppIconView(size: 96)
            Text(verbatim: "Docket").font(.title.bold())
            Text("Version \(info.displayVersion)", comment: "About: version and build").foregroundStyle(.secondary)
            Text("The pull requests waiting on you, from the menu bar.", comment: "About: tagline")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let repository = URL(string: "https://github.com/eliasjnior/docket") {
                Link(
                    String(localized: "github.com/eliasjnior/docket", comment: "About: repository link"),
                    destination: repository)
            }
            HStack {
                Button(String(localized: "Show Data Folder", comment: "About button")) {
                    NSWorkspace.shared.activateFileViewerSelecting([dataFolder])
                }
                Button(String(localized: "What's New", comment: "About button"), action: showWhatsNew)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}
