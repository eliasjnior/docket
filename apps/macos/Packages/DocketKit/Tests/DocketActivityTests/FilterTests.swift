import DocketActivity
import DocketCore
import DocketTestSupport
import Foundation
import Testing

struct FilterTests {
    private func item(
        _ id: String, repository: String = "acme/api", labels: [String] = [], status: Status = .waitingForReview,
        role: Role = .reviewRequested, isDraft: Bool = false, triage: Triage? = .humans
    ) -> WatchedPullRequest {
        var pullRequest = Fixtures.pullRequest(id, repository: repository, isDraft: isDraft)
        pullRequest.labels = labels.map { Label(name: $0, color: "ededed") }
        return WatchedPullRequest(
            pullRequest: pullRequest, role: role, status: status, triage: role == .reviewRequested ? triage : nil)
    }

    @Test func filterOrWithinAndAcross() {
        let items = [
            item("A", repository: "acme/api", labels: ["backend"]),
            item("B", repository: "globex/web", labels: ["urgent"]),
            item("C", repository: "initech/app", labels: ["backend"]),
            item("D", repository: "acme/web", labels: [], status: .checksRunning),
        ]
        let orgs = PopoverFilter(organizations: ["ACME", "globex"])
        #expect(items.filter(orgs.matches).map(\.id) == ["A", "B", "D"])
        let orgsAndLabel = PopoverFilter(organizations: ["acme", "globex"], labels: ["Backend", "urgent"])
        #expect(items.filter(orgsAndLabel.matches).map(\.id) == ["A", "B"])
        #expect(items.filter(PopoverFilter(statuses: [.checksRunning]).matches).map(\.id) == ["D"])
        #expect(items.filter(PopoverFilter(repositories: ["ACME/API"]).matches).map(\.id) == ["A"])
        #expect(PopoverFilter().isEmpty && items.allSatisfy(PopoverFilter().matches))
    }

    @Test func toggleAndClearLatest() {
        var filter = PopoverFilter()
        filter.toggle("acme", in: .organization)
        filter.toggle("backend", in: .label)
        filter.toggle("checksRunning", in: .status)
        filter.toggle("nonsense", in: .status)
        #expect(filter.contains("ACME", in: .organization))
        #expect(filter.contains("checksRunning", in: .status) && !filter.contains("conflict", in: .status))
        #expect(filter.order == [.organization, .label, .status])
        filter.toggle("acme", in: .organization)
        #expect(filter.isEmpty(.organization) && filter.order == [.label, .status])
        filter.toggle("acme/api", in: .repository)
        #expect(filter.clearLatest() && filter.isEmpty(.repository))
        #expect(filter.clearLatest() && filter.clearLatest())
        #expect(!filter.clearLatest() && filter.isEmpty)
    }

    @Test func mineKinds() {
        let conflicted = item("D", status: .conflict, role: .authored, isDraft: true)
        #expect(MineKind.of(conflicted) == .draft)
        #expect(MineKind.of(conflicted, conflictedDrafts: .blocked) == .blocked)
        let failing = item("D", status: .checksFailing, role: .authored, isDraft: true)
        #expect(MineKind.of(failing, conflictedDrafts: .blocked) == .draft)
        #expect(Sections([conflicted], conflictedDrafts: .blocked).mineGroups.map(\.kind) == [.blocked])
        for status in [Status.conflict, .checksFailing, .changesRequested] {
            #expect(MineKind.of(item("B", status: status, role: .authored)) == .blocked)
        }
        for status in [Status.checksRunning, .readyToMerge, .waitingForReview, .noReviewers] {
            #expect(MineKind.of(item("R", status: status, role: .authored)) == .ready)
        }
    }

    @Test func mineGroupsInOrderReadyBlockedDraft() {
        let sections = Sections([
            item("D1", status: .readyToMerge, role: .authored, isDraft: true),
            item("B1", status: .changesRequested, role: .authored),
            item("R1", status: .readyToMerge, role: .authored),
        ])
        #expect(sections.mineGroups.map(\.kind) == [.ready, .blocked, .draft])
        #expect(sections.mine.map(\.id) == ["R1", "B1", "D1"])
    }

    @Test func triagePartitionsReviewRequested() {
        let sections = Sections([
            item("H1", repository: "acme/api"), item("B1", repository: "acme/api", triage: .bots),
            item("S1", repository: "acme/web", triage: .stale), item("H2", repository: "acme/web"),
        ])
        #expect(sections.triageCounts == [.humans: 2, .bots: 1, .stale: 1])
        #expect(sections.reviewRequested(.bots).map(\.repository) == ["acme/api"])
        #expect(sections.reviewRequested(.humans).flatMap(\.items).count == 2)
        #expect(Set(Triage.allCases.flatMap { sections.reviewRequested($0).flatMap(\.items).map(\.id) }).count == 4)
    }

    @Test func mineLayoutDecodesWithADefault() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(Config.self, from: Data("{}".utf8)).mineLayout == .list)
        let board = try decoder.decode(Config.self, from: Data(#"{"mineLayout":"board"}"#.utf8))
        #expect(board.mineLayout == .board)
        #expect(try decoder.decode(Config.self, from: Data(#"{"mineLayout":"grid"}"#.utf8)).mineLayout == .list)
    }
}
