import AppKit
import DocketCore
import DocketStores
import DocketUpdate
import SwiftUI
import UniformTypeIdentifiers

/// The settings window of `docs/05-design.md` §9: toolbar tabs, each a grouped form, saved on change.
struct SettingsView: View {
    let watch: WatchStore
    let configStore: ConfigStore
    let account: AccountSettingsModel
    let permission: NotificationPermission
    let requestPermission: () -> Void
    let checkRepository: (String) async -> Bool
    let updates: UpdateStore
    let info: AppInfo
    let loginItem: LoginItem
    let dataFolder: URL
    let showWhatsNew: () -> Void
    let showPrompt: () -> Void

    var body: some View {
        TabView {
            AccountSettingsView(watch: watch, configStore: configStore, model: account)
                .tabItem {
                    Label(String(localized: "Account", comment: "Settings tab"), systemImage: "person.crop.circle")
                }
            RepositoriesSettingsView(
                selection: SelectionStore(configStore: configStore),
                known: watch.snapshot.cache?.knownRepositories.map(\.name) ?? [], check: checkRepository
            )
            .tabItem { Label(String(localized: "Repositories", comment: "Settings tab"), systemImage: "folder") }
            NotificationsSettingsView(
                configStore: configStore, permission: permission, requestPermission: requestPermission,
                holdSince: watch.snapshot.state.focusHold?.since
            )
            .tabItem { Label(String(localized: "Notifications", comment: "Settings tab"), systemImage: "bell") }
            GeneralSettingsView(configStore: configStore, loginItem: loginItem)
                .tabItem { Label(String(localized: "General", comment: "Settings tab"), systemImage: "gearshape") }
            AISettingsView(configStore: configStore)
                .tabItem {
                    Label(String(localized: "AI & Jira", comment: "Settings tab"), systemImage: "sparkles")
                }
            UpdatesSettingsView(
                configStore: configStore, updates: updates, info: info, showWhatsNew: showWhatsNew,
                showPrompt: showPrompt
            )
            .tabItem { Label(String(localized: "Updates", comment: "Settings tab"), systemImage: "arrow.down.circle") }
            AboutSettingsView(info: info, dataFolder: dataFolder, showWhatsNew: showWhatsNew)
                .tabItem { Label(String(localized: "About", comment: "Settings tab"), systemImage: "info.circle") }
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// What the Account tab shows about `gh`, read when the tab appears.
@MainActor
@Observable
final class AccountSettingsModel {
    var ghLocation: String?
    private let locate: () async -> String?
    let chooseLocation: () -> Void
    let retry: () -> Void

    init(locate: @escaping () async -> String?, chooseLocation: @escaping () -> Void, retry: @escaping () -> Void) {
        self.locate = locate
        self.chooseLocation = chooseLocation
        self.retry = retry
    }

    func refresh() async {
        ghLocation = await locate()
    }
}

struct AccountSettingsView: View {
    let watch: WatchStore
    let configStore: ConfigStore
    @Bindable var model: AccountSettingsModel

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Signed in as", comment: "Account setting")) {
                    Text(verbatim: watch.snapshot.state.viewerLogin.map { "@\($0)" } ?? "—")
                }
                LabeledContent(String(localized: "GitHub CLI", comment: "Account setting")) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(
                            verbatim: configStore.config.ghPath ?? model.ghLocation
                                ?? String(localized: "Not found", comment: "gh location")
                        )
                        .font(.body.monospaced()).textSelection(.enabled)
                        HStack {
                            Button(
                                String(localized: "Choose Location…", comment: "Account setting button"),
                                action: model.chooseLocation)
                            if configStore.config.ghPath != nil {
                                Button(String(localized: "Use Default", comment: "Account setting button")) {
                                    configStore.update { $0.ghPath = nil }
                                    model.retry()
                                }
                            }
                        }
                    }
                }
            }
            Section(String(localized: "Scopes", comment: "Account settings section")) {
                ForEach(["repo", "read:org"], id: \.self) { scope in
                    let missing: Bool = {
                        if case .missingScopes(let scopes) = watch.account { return scopes.contains(scope) }
                        return false
                    }()
                    LabeledContent(scope) {
                        Label(
                            missing
                                ? String(localized: "Missing", comment: "Scope state")
                                : String(localized: "Granted", comment: "Scope state"),
                            systemImage: missing ? "xmark" : "checkmark")
                    }
                }
            }
            if !watch.snapshot.samlOrganizations.isEmpty {
                Section(
                    String(localized: "Organizations needing SAML authorization", comment: "Account settings section")
                ) {
                    ForEach(watch.snapshot.samlOrganizations) { organization in
                        LabeledContent(organization.login) {
                            Link(String(localized: "Authorize", comment: "SAML button"), destination: organization.url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { await model.refresh() }
    }
}

struct GeneralSettingsView: View {
    let configStore: ConfigStore
    var loginItem: LoginItem?
    @State private var importError: String?

    /// FR-96: `config.json` to a file of the user's choice.
    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "docket-config.json"
        panel.allowedContentTypes = [.json]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url, let data = try? configStore.config.exported() else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    /// FR-96: read through the same decoder as the file on disk; a newer or unreadable file is refused.
    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            configStore.replace(with: try Config.imported(from: Data(contentsOf: url)))
            importError = nil
        } catch {
            importError = String(
                localized: "That file is not a Docket settings file this version can read.", comment: "Import error")
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    String(localized: "Count review requests", comment: "Menu bar count setting"),
                    isOn: binding(\.count.includeReviewRequests))
                Toggle(
                    String(localized: "Count your pull requests that need you", comment: "Menu bar count setting"),
                    isOn: binding(\.count.includeBlockedAuthored))
            } header: {
                Text("Menu bar count", comment: "General settings section")
            } footer: {
                Text(
                    "Yours count when they have a conflict, failing checks, requested changes, or are ready to merge.",
                    comment: "Menu bar count caption"
                )
                .font(.caption).foregroundStyle(Color.textSecondary)
            }
            Section(String(localized: "Mine", comment: "General settings section")) {
                Picker(
                    String(localized: "Show your pull requests as", comment: "Mine layout picker"),
                    selection: binding(\.mineLayout)
                ) {
                    Text("List", comment: "Mine layout").tag(Config.MineLayout.list)
                    Text("Board", comment: "Mine layout").tag(Config.MineLayout.board)
                }
                .pickerStyle(.segmented)
            }
            Section(String(localized: "Poll interval", comment: "General settings section")) {
                Picker(
                    String(localized: "Check GitHub every", comment: "Poll interval picker"),
                    selection: binding(\.polling.intervalSeconds)
                ) {
                    Text("30 seconds", comment: "Poll interval").tag(30)
                    Text("1 minute", comment: "Poll interval").tag(60)
                    Text("2 minutes", comment: "Poll interval").tag(120)
                    Text("5 minutes", comment: "Poll interval").tag(300)
                }
                Text(
                    "About \(3600 / configStore.config.polling.intervalSeconds * 4) of GitHub's 5,000 points an hour.",
                    comment: "Caption under the poll interval: the estimated hourly cost"
                )
                .font(.caption).foregroundStyle(Color.textSecondary)
            }
            Section(String(localized: "Keyboard", comment: "General settings section")) {
                Picker(
                    String(localized: "Open Docket with", comment: "Global shortcut picker"),
                    selection: binding(\.shortcut)
                ) {
                    ForEach(Config.Shortcut.allCases, id: \.self) { Text(verbatim: GlobalShortcut.label($0)).tag($0) }
                }
            }
            Section(String(localized: "Settings file", comment: "General settings section")) {
                HStack {
                    Button(String(localized: "Export…", comment: "Export settings button"), action: export)
                    Button(String(localized: "Import…", comment: "Import settings button"), action: importConfig)
                }
                if let importError {
                    Text(verbatim: importError).font(.caption).foregroundStyle(Color.statusAttention)
                }
            }
            if let loginItem {
                Section {
                    Toggle(
                        String(localized: "Open at login", comment: "General setting"),
                        isOn: Binding(
                            get: { loginItem.isEnabled },
                            set: { enabled in
                                loginItem.setEnabled(enabled)
                                configStore.update { $0.launchAtLogin = enabled }
                            }))
                    if loginItem.requiresApproval {
                        Button(
                            String(localized: "Allow in System Settings…", comment: "Login item button"),
                            action: loginItem.openSystemSettings)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding<Value>(_ path: WritableKeyPath<Config, Value>) -> Binding<Value> {
        Binding(
            get: { configStore.config[keyPath: path] },
            set: { value in configStore.update { $0[keyPath: path] = value } })
    }
}
