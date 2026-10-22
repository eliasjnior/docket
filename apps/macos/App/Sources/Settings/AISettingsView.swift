import AppKit
import DocketActivity
import DocketCore
import DocketStores
import SwiftUI
import UniformTypeIdentifiers

/// Settings → AI (spec §9.2): the terminal, the two commands and local clones.
struct AISettingsView: View {
    let configStore: ConfigStore
    @State private var newRepository = ""

    private var integrations: Config.Integrations { configStore.config.integrations }

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Open in", comment: "Terminal picker"), selection: terminal) {
                    Text("Default for .command files", comment: "Terminal picker").tag(String?.none)
                    ForEach(TerminalLauncher.installedTerminals, id: \.path) {
                        Text(verbatim: $0.name).tag(String?.some($0.path))
                    }
                    if let path = integrations.terminalApp,
                        !TerminalLauncher.installedTerminals.contains(where: { $0.path == path })
                    {
                        Text(verbatim: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                            .tag(String?.some(path))
                    }
                }
                Button(String(localized: "Choose Terminal", comment: "Terminal picker button"), action: chooseTerminal)
            } header: {
                Text("Terminal", comment: "AI settings section")
            }
            command(
                String(localized: "Review with AI", comment: "AI settings section"), \.integrations.reviewCommand,
                default: Config.Integrations.defaultReviewCommand)
            command(
                String(localized: "Summarize with AI", comment: "AI settings section"),
                \.integrations.summarizeCommand, default: Config.Integrations.defaultSummarizeCommand)
            Section {
                ForEach(integrations.clones.sorted(by: { $0.key < $1.key }), id: \.key) { entry in
                    LabeledContent(entry.key) {
                        HStack {
                            Text(verbatim: entry.value).font(.body.monospaced()).lineLimit(1).truncationMode(.middle)
                            Button {
                                configStore.update { $0.integrations.clones[entry.key] = nil }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text("Remove clone", comment: "Clones button"))
                        }
                    }
                }
                HStack {
                    TextField(
                        String(localized: "Repository", comment: "Clones field"), text: $newRepository,
                        prompt: Text(verbatim: "acme/api")
                    )
                    .labelsHidden()
                    Button(String(localized: "Choose Folder", comment: "Clones button"), action: chooseClone)
                        .disabled(!newRepository.contains("/"))
                }
            } header: {
                Text("Local clones", comment: "AI settings section")
            } footer: {
                Text(
                    "The command runs in the clone of the pull request's repository, or in a new temporary folder.",
                    comment: "Clones caption"
                )
                .font(.caption).foregroundStyle(Color.textSecondary)
            }
        }
        .formStyle(.grouped)
    }

    private func command(_ title: String, _ path: WritableKeyPath<Config, String>, default value: String) -> some View {
        let text = configStore.config[keyPath: path]
        let literal = CommandScript.placeholdersInSingleQuotes(text)
        return Section {
            TextEditor(
                text: Binding(get: { text }, set: { new in configStore.update { $0[keyPath: path] = new } })
            )
            .font(.body.monospaced())
            .frame(minHeight: 76)
            if !literal.isEmpty {
                Label(
                    String(
                        localized: "Inside single quotes, {\(literal.joined(separator: "}, {"))} is not replaced.",
                        comment: "Command warning"),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption).foregroundStyle(Color.statusAttention)
            }
            if CommandScript.titleStandsAlone(text) {
                Label(
                    String(
                        localized: "Put {title} inside quotes: a title starting with - would be read as an option.",
                        comment: "Command warning"),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption).foregroundStyle(Color.statusAttention)
            }
            if text != value {
                Button(String(localized: "Reset to Default", comment: "Command button")) {
                    configStore.update { $0[keyPath: path] = value }
                }
            }
        } header: {
            Text(verbatim: title)
        } footer: {
            Text("{url}, {repo}, {number}, {title} and {branch} are replaced.", comment: "Command caption")
                .font(.caption).foregroundStyle(Color.textSecondary)
        }
    }

    private var terminal: Binding<String?> {
        Binding(
            get: { integrations.terminalApp },
            set: { value in configStore.update { $0.integrations.terminalApp = value } })
    }

    private func chooseTerminal() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        configStore.update { $0.integrations.terminalApp = url.path }
    }

    private func chooseClone() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let repository = newRepository.trimmingCharacters(in: .whitespaces)
        configStore.update { $0.integrations.clones[repository] = url.path }
        newRepository = ""
    }
}
