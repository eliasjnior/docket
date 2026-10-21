import DocketStores
import DocketUpdate
import SwiftUI

struct UpdatePromptView: View {
    let updates: UpdateStore
    let currentVersion: String
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                AppIconView(size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).font(.title3.bold())
                    Text("You have \(currentVersion).", comment: "Update prompt: the running version").foregroundStyle(
                        .secondary)
                }
            }
            .padding(20)
            Divider()
            if let update = updates.availableUpdate {
                ChangelogView(entries: Changelog.parse(update.notes))
            }
            if case .failed(let message) = updates.phase {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.statusAttention)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            Divider()
            HStack {
                if let update = updates.availableUpdate, !isInstalling {
                    Button(String(localized: "Skip This Version", comment: "Update prompt button")) {
                        updates.skip(update)
                        close()
                    }
                }
                Spacer()
                if isInstalling {
                    ProgressView().controlSize(.small)
                    Text("Installing", comment: "Update prompt state").foregroundStyle(.secondary)
                } else {
                    Button(String(localized: "Later", comment: "Update prompt button")) {
                        updates.dismiss()
                        close()
                    }
                    .keyboardShortcut(.cancelAction)
                    if let update = updates.availableUpdate {
                        Button(String(localized: "Install and Relaunch", comment: "Update prompt button")) {
                            Task { await updates.install(update) }
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 480, height: 460)
    }

    private var title: String {
        updates.availableUpdate.map {
            String(localized: "Docket \($0.version.description) is available", comment: "Update prompt title")
        } ?? String(localized: "Docket update", comment: "Update prompt title")
    }

    private var isInstalling: Bool {
        if case .installing = updates.phase { return true }
        return false
    }
}
