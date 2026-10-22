import DocketCore
import DocketPersistence
import DocketStores
import DocketTestSupport
import Foundation
import Testing

@MainActor
struct SelectionStoreTests {
    private func configStore() -> (ConfigStore, FileStores) {
        let files = FileStores(
            paths: AppPaths(root: FileManager.default.temporaryDirectory.appending(path: "docket-\(UUID().uuidString)"))
        )
        return (ConfigStore(storage: files), files)
    }

    @Test func selectionEntriesFollowTheMode() {
        let (store, _) = configStore()
        let selection = SelectionStore(configStore: store)
        selection.add(.repository("acme/legacy"))
        selection.add(.owner("corp"))
        selection.add(.repository("ACME/legacy"))
        #expect(store.config.selection.excludedRepositories == ["acme/legacy"])
        #expect(selection.entries == [.owner("corp"), .repository("acme/legacy")])
        selection.setMode(.only)
        #expect(selection.entries.isEmpty)
        selection.add(.repository("acme/api"))
        #expect(store.config.selection.includedRepositories == ["acme/api"])
        selection.remove(.repository("ACME/API"))
        #expect(store.config.selection.includedRepositories.isEmpty)
        selection.setMode(.all)
        selection.remove(.owner("corp"))
        #expect(selection.entries == [.repository("acme/legacy")])
    }

    @Test(arguments: [
        ("acme/api", SelectionStore.Entry.repository("acme/api")), (" acme ", .owner("acme")),
    ])
    func typedEntries(text: String, entry: SelectionStore.Entry) {
        #expect(SelectionStore.Entry(typed: text) == entry)
    }

    @Test(arguments: ["", "a/b/c", "acme/", "/api", "acme api"])
    func invalidTypedEntries(text: String) {
        #expect(SelectionStore.Entry(typed: text) == nil)
    }
}
