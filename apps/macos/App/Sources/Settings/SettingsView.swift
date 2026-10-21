import DocketCore
import DocketStores
import SwiftUI

/// The settings window of `docs/05-design.md` §9: toolbar tabs, each a grouped form, saved on change.
struct SettingsView: View {
    let watch: WatchStore
    let configStore: ConfigStore
    let account: AccountSettingsModel

    var body: some View {
        TabView {
            AccountSettingsView(watch: watch, configStore: configStore, model: account)
                .tabItem {
                    Label(String(localized: "Account", comment: "Settings tab"), systemImage: "person.crop.circle")
                }
            GeneralSettingsView(configStore: configStore)
                .tabItem { Label(String(localized: "General", comment: "Settings tab"), systemImage: "gearshape") }
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

    var body: some View {
        Form {
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
        }
        .formStyle(.grouped)
    }

    private func binding<Value>(_ path: WritableKeyPath<Config, Value>) -> Binding<Value> {
        Binding(
            get: { configStore.config[keyPath: path] },
            set: { value in configStore.update { $0[keyPath: path] = value } })
    }
}
