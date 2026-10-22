import DocketActivity
import DocketCore
import DocketTestSupport
import Foundation
import Testing

struct PollEngineTests {
    private let now = Fixtures.now
    private let viewer = ViewerContext(login: "you", teams: ["acme": ["backend"]])

    private func input(
        _ pullRequests: [PullRequest], details: [PullRequestDetail] = [], state: PersistedState = PersistedState(),
        discovery: Discovery = Discovery(), failed: [String] = [], cache: SnapshotCache? = nil,
        config: Config = Config(), at: Date? = nil
    ) -> PollInput {
        PollInput(
            viewer: viewer, now: at ?? now, config: config, state: state, previousCache: cache, discovery: discovery,
            summaries: SummaryBatch(pullRequests: pullRequests, failed: failed),
            details: Dictionary(uniqueKeysWithValues: details.map { ($0.id, $0) }))
    }

    @Test func summariesCoverCandidatesAndTheWatchSet() {
        let state = PersistedState(cursors: [
            "PR_9": Cursor(ref: "acme/api#9", role: .involved, updatedAt: now, enteredAt: now),
            "PR_8": Cursor(ref: "acme/api#8", role: nil, updatedAt: now, enteredAt: now, leftAt: now),
            "PR_1": Cursor(ref: "acme/api#1", role: .authored, updatedAt: now, enteredAt: now),
        ])
        let ids = PollEngine.summaryIDs(discovery: Discovery(authored: ["PR_1"], requested: ["PR_2"]), state: state)
        #expect(ids == ["PR_1", "PR_2", "PR_9"])
    }

    @Test func detailsAreReadOnEntryAndOnChangeOnly() {
        let unchanged = Fixtures.pullRequest("PR_1", author: "you")
        let changed = Fixtures.pullRequest("PR_2", author: "you")
        let new = Fixtures.pullRequest("PR_3", author: "you")
        let stranger = Fixtures.pullRequest("PR_4")
        let team = Fixtures.pullRequest("PR_5", requests: [.team(organization: "acme", slug: "backend")])
        let state = PersistedState(cursors: [
            "PR_1": Cursor(ref: "", role: .authored, updatedAt: unchanged.updatedAt, enteredAt: now),
            "PR_2": Cursor(ref: "", role: .authored, updatedAt: now.addingTimeInterval(-9999), enteredAt: now),
        ])
        let ids = PollEngine.detailIDs(
            summaries: [unchanged, changed, new, stranger, team], discovery: Discovery(), state: state, viewer: viewer,
            now: now)
        #expect(ids == ["PR_2", "PR_3", "PR_5"])
    }

    @Test("Worked example #1: the fresh-install baseline lists everything and notifies nothing")
    func example1() {
        let requests = (1...4).map { index in
            Fixtures.pullRequest(
                "PR_\(index)", number: index, repository: index <= 2 ? "acme/api" : "acme/web",
                requests: [.user(login: "you")])
        }
        let details = requests.map { pullRequest in
            PullRequestDetail(
                id: pullRequest.id,
                requestEvents: [Fixtures.request("E_\(pullRequest.id)", at: now.addingTimeInterval(-600))])
        }
        let output = PollEngine.run(input(requests, details: details))
        #expect(output.notifications.isEmpty)
        #expect(output.events.isEmpty)
        #expect(output.state.baselineAt == now)
        #expect(output.cache.pullRequests.count == 4)
        let items = Watch.items(
            cache: output.cache.pullRequests, config: Config(), state: output.state, now: Fixtures.now)
        #expect(Count.count(items) == 4)
        #expect(output.state.cursors["PR_1"]?.seen == ["E_PR_1"])
        #expect(output.state.cursors["PR_1"]?.enteredAt == now)
    }

    @Test("Worked example #15: a renamed repository keeps its cursor and shows the new name")
    func example15() {
        let before = Fixtures.pullRequest("PR_1", repository: "acme/api", author: "you")
        let first = PollEngine.run(input([before], details: [PullRequestDetail(id: "PR_1")]))
        var renamed = before
        renamed.repository = "acme/core"
        let second = PollEngine.run(
            input([renamed], state: first.state, cache: first.cache, at: now.addingTimeInterval(60)))
        #expect(second.state.cursors["PR_1"]?.enteredAt == now)
        #expect(second.state.cursors["PR_1"]?.ref == "acme/core#482")
        #expect(second.cache.pullRequests.first?.pullRequest.repository == "acme/core")
        #expect(second.notifications.isEmpty)
    }

    @Test func aPullRequestThatLosesItsRoleLeavesAndKeepsItsCursor() {
        let mine = Fixtures.pullRequest("PR_1", author: "you")
        let first = PollEngine.run(input([mine], details: [PullRequestDetail(id: "PR_1")]))
        var merged = mine
        merged.state = .merged
        var marked = first.state
        marked.marked = ["PR_1"]
        let later = now.addingTimeInterval(60)
        let second = PollEngine.run(input([merged], state: marked, cache: first.cache, at: later))
        #expect(second.state.cursors["PR_1"]?.role == nil)
        #expect(second.state.cursors["PR_1"]?.leftAt == later)
        #expect(second.state.marked.isEmpty)
        #expect(second.cache.pullRequests.isEmpty)
    }

    @Test func aFailedNodeKeepsItsPreviousSnapshot() {
        let mine = Fixtures.pullRequest("PR_1", author: "you")
        let first = PollEngine.run(input([mine], details: [PullRequestDetail(id: "PR_1")]))
        let second = PollEngine.run(input([], state: first.state, failed: ["PR_1"], cache: first.cache))
        #expect(second.cache.pullRequests.map(\.id) == ["PR_1"])
        #expect(second.state.cursors["PR_1"]?.role == .authored)
    }

    @Test func anExcludedRepositoryLeavesTheWatchSet() {
        let pullRequest = Fixtures.pullRequest("PR_1", repository: "acme/legacy", author: "you")
        let output = PollEngine.run(
            input(
                [pullRequest], details: [PullRequestDetail(id: "PR_1")],
                config: Config(selection: Selection(excludedRepositories: ["acme/legacy"]))))
        #expect(output.cache.pullRequests.isEmpty)
        #expect(output.state.cursors["PR_1"] == nil)
        #expect(output.cache.knownRepositories.map(\.name) == ["acme/legacy"])
    }

    @Test func theCacheCarriesTheRequestAndCommenters() {
        let team = Reviewer.team(organization: "acme", slug: "backend")
        let requested = Fixtures.pullRequest("PR_1", requests: [team])
        let mine = Fixtures.pullRequest("PR_2", author: "you")
        let details = [
            PullRequestDetail(
                id: "PR_1",
                requestEvents: [Fixtures.request("E1", to: team, by: "ana", at: now.addingTimeInterval(-3600))]),
            PullRequestDetail(id: "PR_2", reviews: [Fixtures.review("R1", by: "dave", .commented, at: now)]),
        ]
        let first = PollEngine.run(input([requested, mine], details: details))
        let byID = Dictionary(uniqueKeysWithValues: first.cache.pullRequests.map { ($0.id, $0) })
        #expect(
            byID["PR_1"]?.request
                == RequestInfo(requestedAt: now.addingTimeInterval(-3600), requestedBy: "ana", team: team))
        #expect(byID["PR_2"]?.commenters == ["dave"])
        #expect(byID["PR_2"]?.request == nil)
        let second = PollEngine.run(input([requested, mine], state: first.state, cache: first.cache))
        #expect(second.cache.pullRequests == first.cache.pullRequests)
    }

    @Test func knownRepositoriesExpireAfterNinetyDays() {
        let old = KnownRepository(name: "acme/old", lastSeenAt: now.addingTimeInterval(-Fixtures.days(91)))
        let recent = KnownRepository(name: "acme/web", lastSeenAt: now.addingTimeInterval(-Fixtures.days(3)))
        let cache = SnapshotCache(fetchedAt: now, viewerLogin: "you", knownRepositories: [old, recent])
        let output = PollEngine.run(input([Fixtures.pullRequest(author: "you")], cache: cache))
        #expect(output.cache.knownRepositories.map(\.name) == ["acme/api", "acme/web"])
    }
}
