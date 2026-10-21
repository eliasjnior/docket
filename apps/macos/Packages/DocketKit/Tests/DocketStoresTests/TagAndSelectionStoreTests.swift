import DocketCore
import DocketPersistence
import DocketStores
import DocketTestSupport
import Foundation
import Testing

@MainActor
struct TagAndSelectionStoreTests {
    private func configStore() -> (ConfigStore, FileStores) {
        let files = FileStores(
            paths: AppPaths(root: FileManager.default.temporaryDirectory.appending(path: "docket-\(UUID().uuidString)"))
        )
        return (ConfigStore(storage: files), files)
    }

    @Test("M3 Done when: ` WIP ` is stored as `wip` under the node ID, and survives a relaunch")
    func tagsAreNormalizedAndKeyedByNodeID() async throws {
        let (store, files) = configStore()
        let tags = TagStore(configStore: store, now: { Fixtures.now })
        #expect(tags.add(" WIP ", to: "PR_kw1", ref: "acme/api#482") == .success("wip"))
        #expect(tags.add("wip", to: "PR_kw1", ref: "acme/api#482") == .failure(.alreadyAdded))
        #expect(tags.add("a/b", to: "PR_kw1", ref: "acme/api#482") == .failure(.invalidCharacters))
        try await Task.sleep(for: .milliseconds(50))
        let saved = try await files.loadConfig()
        #expect(saved.tags["PR_kw1"] == Config.TagEntry(ref: "acme/api#482", tags: ["wip"], updatedAt: Fixtures.now))
        let relaunched = ConfigStore(storage: files)
        await relaunched.load()
        #expect(TagStore(configStore: relaunched).tags(of: "PR_kw1") == ["wip"])
        tags.remove("wip", from: "PR_kw1", ref: "acme/api#482")
        #expect(store.config.tags["PR_kw1"] == nil)
    }

    @Test func fiveTagsAtMost() {
        let (store, _) = configStore()
        let tags = TagStore(configStore: store)
        for tag in ["a", "b", "c", "d", "e"] { tags.add(tag, to: "PR_1", ref: "acme/api#1") }
        #expect(tags.add("f", to: "PR_1", ref: "acme/api#1") == .failure(.tooMany))
        #expect(tags.inUse == ["a", "b", "c", "d", "e"])
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
