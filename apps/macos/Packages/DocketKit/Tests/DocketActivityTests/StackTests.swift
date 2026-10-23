import DocketActivity
import DocketCore
import DocketTestSupport
import Foundation
import Testing

struct StackTests {
    private func item(
        _ id: String, _ number: Int, head: String, base: String, repository: String = "acme/api",
        role: Role = .authored, activeHours: Double = 1
    ) -> WatchedPullRequest {
        var pullRequest = Fixtures.pullRequest(id, number: number, repository: repository, author: "you")
        pullRequest.headRefName = head
        pullRequest.baseRefName = base
        return WatchedPullRequest(
            pullRequest: pullRequest, role: role, status: .noReviewers,
            lastActivity: Fixtures.now.addingTimeInterval(-Fixtures.hours(activeHours)))
    }

    @Test("Worked example #50: three pull requests on one another are one stack, bottom first")
    func example50() {
        let rows = [
            item("C", 3, head: "page", base: "plug"), item("A", 1, head: "matcher", base: "main"),
            item("B", 2, head: "plug", base: "matcher"), item("X", 9, head: "other", base: "main"),
        ]
        let stacks = Stacks.find(rows)
        #expect(stacks.map { $0.items.map(\.id) } == [["A", "B", "C"]])
        #expect(stacks.first?.base == "main")
        let arranged = Stacks.arrange(rows)
        #expect(arranged.map(\.id) == ["A", "B", "C", "X"])
        #expect(
            arranged.map(\.stackPosition) == [
                StackPosition(index: 1, count: 3), StackPosition(index: 2, count: 3), StackPosition(index: 3, count: 3),
                nil,
            ])
    }

    @Test func aStackSumsItsChangesAndTakesItsWorstStatusLatestActivityAndOldestAge() {
        var bottom = item("A", 1, head: "matcher", base: "main", activeHours: 30 * 24)
        bottom.pullRequest.createdAt = Fixtures.now.addingTimeInterval(-Fixtures.days(40))
        bottom.pullRequest.additions = 100
        bottom.pullRequest.deletions = 20
        bottom.pullRequest.changedFiles = 4
        bottom.status = .waitingForReview
        var top = item("B", 2, head: "plug", base: "matcher", activeHours: 10 * 24)
        top.pullRequest.additions = 50
        top.pullRequest.deletions = 5
        top.pullRequest.changedFiles = 2
        top.status = .conflict
        let stack = Stack(repository: "acme/api", items: [bottom, top])
        #expect(stack.additions == 150 && stack.deletions == 25 && stack.changedFiles == 6)
        #expect(stack.status == .conflict)
        #expect(stack.createdAt == bottom.pullRequest.createdAt)
        #expect(stack.lastActivity == top.lastActivity)
        #expect(stack.isStale(now: Fixtures.now, staleAfterDays: 7))
        #expect(!stack.isStale(now: Fixtures.now, staleAfterDays: 14))
        top.pullRequest.additions = nil
        #expect(Stack(repository: "acme/api", items: [bottom, top]).additions == nil)
    }

    @Test func aBranchOfTheSameNameInAnotherRepositoryIsNotAStack() {
        let rows = [
            item("A", 1, head: "feature", base: "main"),
            item("B", 2, head: "next", base: "feature", repository: "acme/web"),
        ]
        #expect(Stacks.find(rows).isEmpty)
    }

    @Test func twoOnOneBaseStayInOneStackLowerNumberFirst() {
        let rows = [
            item("T", 7, head: "two", base: "root"), item("R", 5, head: "root", base: "main"),
            item("O", 6, head: "one", base: "root"),
        ]
        #expect(Stacks.find(rows).map { $0.items.map(\.id) } == [["R", "O", "T"]])
    }

    @Test func mineListsAStackWholeInOneGroupAndTheBoardKeepsItsCardsInTheirColumns() {
        var bottom = item("A", 1, head: "matcher", base: "main", activeHours: 5)
        bottom.status = .readyToMerge
        var top = item("B", 2, head: "plug", base: "matcher", activeHours: 2)
        top.status = .conflict
        let single = item("X", 9, head: "other", base: "main", activeHours: 3)
        let sections = Sections([bottom, top, single])
        #expect(sections.mineStacks.map { $0.items.map(\.id) } == [["A", "B"]])
        // The conflict makes the stack Blocked; in the list it stays whole there, bottom first.
        #expect(sections.mineListGroups.map(\.kind) == [.ready, .blocked])
        #expect(sections.mineListGroups.last?.items.map(\.id) == ["A", "B"])
        #expect(sections.mineGroups.first { $0.kind == .ready }?.items.map(\.id) == ["X", "A"])
        #expect(sections.mine.first { $0.id == "B" }?.stackPosition == StackPosition(index: 2, count: 2))
    }

    @Test func aStackOfDraftsIsADraftAndAMixedOneIsReady() {
        var draft = item("A", 1, head: "one", base: "main")
        draft.pullRequest.isDraft = true
        var other = item("B", 2, head: "two", base: "one")
        other.pullRequest.isDraft = true
        #expect(Sections.kind(of: Stack(repository: "acme/api", items: [draft, other])) == .draft)
        other.pullRequest.isDraft = false
        #expect(Sections.kind(of: Stack(repository: "acme/api", items: [draft, other])) == .ready)
    }
}
