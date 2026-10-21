import DocketCore
import Testing

@testable import DocketUpdate

struct ChangelogTests {
    private let markdown = """
        # Changelog

        ## [0.3.0](https://github.com/owner/repo/compare/macos-v0.2.0...macos-v0.3.0) (2026-10-19)


        ### New

        * **macos:** add price alerts with notifications ([#16](https://github.com/owner/repo/issues/16)) ([dca06ed](https://github.com/owner/repo/commit/dca06ed))

        ### Fixed

        * reconnect after sleep ([#20](https://github.com/owner/repo/issues/20)) ([abc1234](https://github.com/owner/repo/commit/abc1234))

        ## [0.2.0](https://github.com/owner/repo/compare/macos-v0.1.0...macos-v0.2.0) (2026-10-18)

        ### New

        * **macos:** show live prices ([#12](https://github.com/owner/repo/issues/12)) ([4991afc](https://github.com/owner/repo/commit/4991afc))

        ## 0.1.0 (2026-10-17)

        ### New

        * **macos:** add settings window
        """

    @Test func parsesEntriesNewestFirst() {
        let entries = Changelog.parse(markdown)
        #expect(entries.map(\.version.description) == ["0.3.0", "0.2.0", "0.1.0"])
        #expect(entries[0].date == "2026-10-19")
        #expect(entries[0].sections.map(\.title) == ["New", "Fixed"])
        #expect(entries[0].sections[0].items == ["Add price alerts with notifications"])
        #expect(entries[0].sections[1].items == ["Reconnect after sleep"])
        #expect(entries[2].sections[0].items == ["Add settings window"])
    }

    @Test func slicesBetweenVersions() throws {
        let entries = Changelog.parse(markdown)
        let sliced = Changelog.entries(
            entries, after: SemanticVersion("0.1.0"), upTo: try #require(SemanticVersion("0.2.0")))
        #expect(sliced.map(\.version.description) == ["0.2.0"])
        #expect(Changelog.entries(entries, after: nil, upTo: try #require(SemanticVersion("0.3.0"))).count == 3)
        #expect(
            Changelog.entries(entries, after: SemanticVersion("0.3.0"), upTo: try #require(SemanticVersion("0.3.0")))
                .isEmpty)
    }
}
