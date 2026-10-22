import DocketCore
import DocketStores
import SwiftUI

/// Settings → Repositories (`docs/05-design.md` §9): the mode, the list for it, and the picker.
struct RepositoriesSettingsView: View {
    let selection: SelectionStore
    let known: [String]
    let check: (String) async -> Bool
    @State private var picking = false
    @State private var selected: SelectionStore.Entry?

    var body: some View {
        Form {
            Picker(selection: Binding(get: { selection.mode }, set: { selection.setMode($0) })) {
                Text("All repositories except these", comment: "Selection mode").tag(Selection.Mode.all)
                Text("Only these repositories", comment: "Selection mode").tag(Selection.Mode.only)
            } label: {
                EmptyView()
            }
            .pickerStyle(.radioGroup)
            Section {
                List(selection: $selected) {
                    ForEach(selection.entries, id: \.self) { entry in
                        Label {
                            Text(verbatim: entry.name)
                        } icon: {
                            Image(
                                systemName: {
                                    if case .owner = entry { return "building.2" } else { return "folder" }
                                }())
                        }
                        .tag(entry)
                    }
                }
                .frame(minHeight: 120)
                HStack {
                    Button {
                        picking = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("Add", comment: "Repositories list button"))
                    Button {
                        if let selected { selection.remove(selected) }
                        selected = nil
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selected == nil)
                    .accessibilityLabel(Text("Remove", comment: "Repositories list button"))
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $picking) {
            RepositoryPicker(known: known, existing: Set(selection.entries.map(\.name)), check: check) { entry in
                selection.add(entry)
            } close: {
                picking = false
            }
        }
    }
}

/// The picker of FR-73: repositories seen in the last 90 days, and the typed `owner/name` first.
struct RepositoryPicker: View {
    let known: [String]
    let existing: Set<String>
    let check: (String) async -> Bool
    let add: (SelectionStore.Entry) -> Void
    let close: () -> Void
    @State private var query = ""
    @State private var status: Status?

    private enum Status: Equatable {
        case checking
        case notFound
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(String(localized: "owner/name or organization", comment: "Repository picker field"), text: $query)
                .onSubmit(addTyped)
            if let status {
                Text(
                    status == .checking
                        ? String(localized: "Checking…", comment: "Repository picker")
                        : String(localized: "Not found, or you don't have access", comment: "Repository picker")
                )
                .font(.caption).foregroundStyle(Color.textSecondary)
            }
            List {
                if let typed = SelectionStore.Entry(typed: query),
                    !known.contains(where: { $0.caseInsensitiveCompare(typed.name) == .orderedSame })
                {
                    Button(action: addTyped) { Text(verbatim: typed.name) }.buttonStyle(.borderless)
                }
                ForEach(matches, id: \.self) { name in
                    Button {
                        add(.repository(name))
                        close()
                    } label: {
                        Text(verbatim: name)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .frame(minHeight: 200)
            HStack {
                Spacer()
                Button(String(localized: "Cancel", comment: "Repository picker"), action: close).keyboardShortcut(
                    .cancelAction)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private var matches: [String] {
        known.filter { name in
            !existing.contains(name) && (query.isEmpty || name.localizedCaseInsensitiveContains(query))
        }
    }

    private func addTyped() {
        guard let entry = SelectionStore.Entry(typed: query) else { return }
        guard case .repository(let name) = entry else {
            add(entry)
            close()
            return
        }
        status = .checking
        Task {
            if await check(name) {
                add(entry)
                close()
            } else {
                status = .notFound
            }
        }
    }
}
