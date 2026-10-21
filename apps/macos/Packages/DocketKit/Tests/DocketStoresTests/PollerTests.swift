import DocketActivity
import DocketCore
import DocketGitHub
import DocketPersistence
import DocketStores
import DocketTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct PollerTests {
    private let now = Fixtures.now

    private func world(_ pullRequests: [PullRequest], details: [PullRequestDetail] = []) -> GitHubWorld {
        var world = GitHubWorld()
        world.pullRequests = pullRequests
        world.details = Dictionary(uniqueKeysWithValues: details.map { ($0.id, $0) })
        world.discovery = Discovery(
            authored: pullRequests.filter { $0.author?.login == "you" }.map(\.id),
            requested: pullRequests.filter { !$0.reviewRequests.isEmpty }.map(\.id))
        return world
    }

    @Test func aPollWritesStateAndCacheAndPublishesTheList() async throws {
        let mine = Fixtures.pullRequest("PR_1", author: "you", checks: .failure)
        let requested = Fixtures.pullRequest("PR_2", number: 9, requests: [.user(login: "you")])
        let harness = Harness(world: world([mine, requested]))
        let snapshot = await harness.poll()
        #expect(snapshot.account == .ready)
        #expect(snapshot.cache?.pullRequests.count == 2)
        #expect(!snapshot.isPolling)
        let state = try #require(await harness.state())
        #expect(state.viewerLogin == "you")
        #expect(state.baselineAt != nil)
        #expect(state.lastPoll?.limit == 5000)
        #expect(harness.sink.all.isEmpty)
        let items = Watch.items(cache: snapshot.cache?.pullRequests ?? [], config: Config(), state: state)
        #expect(Count.count(items) == 2)
    }

    @Test func startPublishesTheCacheBeforeTheFirstPoll() async throws {
        let first = Harness(world: world([Fixtures.pullRequest("PR_1", author: "you")]))
        _ = await first.poll()
        var world = GitHubWorld()
        world.status = 502
        let second = first.relaunch(world: world)
        let published = second.published
        await second.poller.start { snapshot in published.append(snapshot) }
        let initial = try #require(published.all.first)
        #expect(initial.account == .loading)
        #expect(initial.cache?.pullRequests.map(\.id) == ["PR_1"])
        await second.poller.stop()
    }

    @Test func noGhIsItsOwnScreen() async {
        let harness = Harness(world: GitHubWorld(), ghFound: false)
        #expect(await harness.poll().account == .ghNotFound)
    }

    @Test func aSignedOutGhIsItsOwnScreen() async {
        let harness = Harness(world: GitHubWorld())
        harness.runner.set(CommandResult(status: 1, output: ""))
        #expect(await harness.poll().account == .signedOut)
    }

    @Test func missingScopesAreNamed() async {
        var world = GitHubWorld()
        world.scopes = "repo"
        #expect(await Harness(world: world).poll().account == .missingScopes(["read:org"]))
    }

    @Test func a401AfterReReadingIsSignedOut() async {
        var world = GitHubWorld()
        world.status = 401
        #expect(await Harness(world: world).poll().account == .signedOut)
    }

    @Test func aServerErrorKeepsTheListAndSaysSo() async throws {
        let harness = Harness(world: world([Fixtures.pullRequest("PR_1", author: "you")]))
        _ = await harness.poll()
        GitHubWorld.update { $0.status = 502 }
        let snapshot = await harness.poll()
        #expect(snapshot.cache?.pullRequests.count == 1)
        if case .failed = snapshot.problem {
        } else {
            Issue.record("expected a failed poll, got \(String(describing: snapshot.problem))")
        }
    }

    @Test func underTwentyPercentNoPollRunsUntilTheReset() async throws {
        var world = world([Fixtures.pullRequest("PR_1", author: "you")])
        world.remaining = 900
        let harness = Harness(world: world)
        let first = await harness.poll()
        #expect(first.problem == .rateLimited(until: now.addingTimeInterval(3600)))
        let served = GitHubWorld.queries.count
        _ = await harness.poll()
        #expect(GitHubWorld.queries.count == served)
        harness.clock.advance(3601)
        _ = await harness.poll()
        #expect(GitHubWorld.queries.count > served)
    }

    @Test func offlineNoPollRunsAndReconnectingPollsOnce() async throws {
        let harness = Harness(world: world([Fixtures.pullRequest("PR_1", author: "you")]))
        await harness.poller.setOnline(false)
        #expect(await harness.poll().problem == .offline)
        #expect(GitHubWorld.queries.isEmpty)
        await harness.poller.setOnline(true)
        #expect(await harness.poller.current().account == .ready)
        #expect(!GitHubWorld.queries.isEmpty)
    }

    @Test func aDifferentLoginStartsAFreshBaseline() async throws {
        let harness = Harness(world: world([Fixtures.pullRequest("PR_1", author: "you")]))
        _ = await harness.poll()
        var other = world([Fixtures.pullRequest("PR_7", author: "dave")])
        other.login = "dave"
        other.discovery = Discovery(authored: ["PR_7"])
        let relaunched = harness.relaunch(world: other)
        _ = await relaunched.poll()
        let state = try #require(await relaunched.state())
        #expect(state.viewerLogin == "dave")
        #expect(state.cursors.keys.sorted() == ["PR_7"])
    }

    @Test func teamsAreReadOncePerHour() async throws {
        let team = Reviewer.team(organization: "acme", slug: "backend")
        var world = world([Fixtures.pullRequest("PR_1", requests: [team])])
        world.teams = ["acme": ["backend"]]
        let harness = Harness(world: world)
        let first = await harness.poll()
        #expect(first.cache?.pullRequests.first?.role == .reviewRequested)
        _ = await harness.poll()
        #expect(GitHubWorld.queries.filter { $0.contains("organization(login") }.count == 1)
        harness.clock.advance(3601)
        _ = await harness.poll()
        #expect(GitHubWorld.queries.filter { $0.contains("organization(login") }.count == 2)
    }

    @Test func theServerClockCorrectsNow() async throws {
        var world = world([Fixtures.pullRequest("PR_1", author: "you")])
        world.serverDate = now.addingTimeInterval(120)
        let harness = Harness(world: world)
        _ = await harness.poll()
        let state = try #require(await harness.state())
        #expect(state.lastPoll?.serverTimeOffset == 120)
        #expect(state.baselineAt == now.addingTimeInterval(120))
    }

    @Test func bookkeepingIsWrittenAndPublished() async throws {
        let harness = Harness(world: world([]))
        await harness.poller.updateState { $0.popoverOpenedAt = Fixtures.now }
        #expect(try #require(await harness.state()).popoverOpenedAt == now)
        #expect(await harness.poller.current().state.popoverOpenedAt == now)
    }

    @Test func pollIfOlderSkipsAFreshList() async throws {
        let harness = Harness(world: world([Fixtures.pullRequest("PR_1", author: "you")]))
        _ = await harness.poll()
        let served = GitHubWorld.queries.count
        await harness.poller.pollIfOlder(than: 30)
        #expect(GitHubWorld.queries.count == served)
        harness.clock.advance(31)
        await harness.poller.pollIfOlder(than: 30)
        #expect(GitHubWorld.queries.count > served)
    }
}
