import DocketActivity
import DocketCore
import DocketTestSupport
import Foundation
import Testing

struct HumanActivityTests {
    private let now = Fixtures.now

    private func at(_ hoursAgo: Double) -> Date { now.addingTimeInterval(-Fixtures.hours(hoursAgo)) }

    @Test func stampsKeepLatestPerLogin() {
        let detail = PullRequestDetail(
            id: "PR_1",
            reviews: [Fixtures.review("R1", by: "ana", at: at(5))],
            comments: [Fixtures.comment("C1", by: "ana", at: at(2)), Fixtures.comment("C2", by: "bruno", at: at(4))],
            threads: [ReviewThread(id: "T1", comments: [Fixtures.threadComment("TC1", by: "Ana", at: at(1))])],
            requestEvents: [Fixtures.request("E1", by: "carla", at: at(6))])
        let stamps = HumanActivity.stamps(in: detail)
        #expect(stamps.map(\.login) == ["Ana", "bruno", "carla"])
        #expect(stamps.first?.at == at(1))
    }

    @Test func botPushIsNotHumanActivity() {
        var pullRequest = Fixtures.pullRequest()
        pullRequest.headCommit = CommitStamp(login: nil, isBot: true, at: at(1))
        pullRequest.lastForcePush = ActivityStamp(login: "dependabot", isBot: true, at: at(1))
        let cached = CachedPullRequest(
            pullRequest: pullRequest, role: .reviewRequested,
            activity: [ActivityStamp(login: "ana", at: at(10)), ActivityStamp(login: "ci-bot[bot]", at: at(2))])
        #expect(HumanActivity.last(cached, extra: []) == at(10))
    }

    @Test func humanCommitAndPushCount() {
        var pullRequest = Fixtures.pullRequest()
        pullRequest.headCommit = CommitStamp(login: "ana", at: at(3))
        #expect(
            HumanActivity.last(CachedPullRequest(pullRequest: pullRequest, role: .reviewRequested), extra: []) == at(3))
        pullRequest.lastForcePush = ActivityStamp(login: "ana", at: at(1))
        #expect(
            HumanActivity.last(CachedPullRequest(pullRequest: pullRequest, role: .reviewRequested), extra: []) == at(1))
    }

    @Test func viewerExcludedForOthers() {
        var pullRequest = Fixtures.pullRequest(author: "you")
        pullRequest.headCommit = CommitStamp(login: "you", at: at(1))
        let cached = CachedPullRequest(
            pullRequest: pullRequest, role: .authored,
            activity: [ActivityStamp(login: "You", at: at(2)), ActivityStamp(login: "ana", at: at(8))])
        #expect(HumanActivity.last(cached, extra: []) == at(1))
        #expect(HumanActivity.last(cached, excluding: "you", extra: []) == at(8))
    }

    @Test func extraBotLoginsApplyAtReadTime() {
        let cached = CachedPullRequest(
            pullRequest: Fixtures.pullRequest(), role: .reviewRequested,
            activity: [ActivityStamp(login: "renovate", at: at(1)), ActivityStamp(login: "ana", at: at(9))])
        #expect(HumanActivity.last(cached, extra: []) == at(1))
        #expect(HumanActivity.last(cached, extra: ["Renovate"]) == at(9))
        #expect(
            HumanActivity.last(CachedPullRequest(pullRequest: Fixtures.pullRequest(), role: .involved), extra: [])
                == nil)
    }

    @Test func botTestCoversTypeSuffixAndList() {
        #expect(Bots.isBot(Actor(login: "ci", isBot: true), extra: []))
        #expect(Bots.isBot(Actor(login: "github-actions[bot]"), extra: []))
        #expect(Bots.isBot(Actor(login: "renovate"), extra: ["RENOVATE"]))
        #expect(!Bots.isBot(Actor(login: "ana"), extra: ["renovate"]))
        #expect(!Bots.isBot(nil, extra: []))
        #expect(Bots.isBot(commit: CommitStamp(login: "renovate", at: now), extra: ["renovate"]))
        #expect(Bots.isBot(commit: CommitStamp(login: nil, isBot: true, at: now), extra: []))
        #expect(!Bots.isBot(commit: CommitStamp(login: nil, at: now), extra: []))
    }

    @Test func pollKeepsActivityWithoutADetail() {
        let viewer = ViewerContext(login: "you", teams: nil)
        let pullRequest = Fixtures.pullRequest(requests: [.user(login: "you")])
        let detail = PullRequestDetail(id: "PR_1", comments: [Fixtures.comment("C1", by: "ana", at: at(2))])
        let first = PollEngine.run(
            PollInput(
                viewer: viewer, now: now, summaries: SummaryBatch(pullRequests: [pullRequest]),
                details: ["PR_1": detail]))
        #expect(first.cache.pullRequests.first?.activity == [ActivityStamp(login: "ana", at: at(2))])
        let second = PollEngine.run(
            PollInput(
                viewer: viewer, now: now, state: first.state, previousCache: first.cache,
                summaries: SummaryBatch(pullRequests: [pullRequest])))
        #expect(second.cache.pullRequests.first?.activity == first.cache.pullRequests.first?.activity)
    }

    @Test func oldCacheEntriesStillDecode() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let json = """
            {"pullRequest":{"id":"PR_1","number":1,"title":"t","url":"https://github.com/acme/api/pull/1",
            "state":"OPEN","isDraft":false,"createdAt":"2026-10-19T12:00:00Z","updatedAt":"2026-10-19T12:00:00Z",
            "repository":"acme/api"},"role":"reviewRequested"}
            """
        let cached = try decoder.decode(CachedPullRequest.self, from: Data(json.utf8))
        #expect(cached.activity.isEmpty && cached.pullRequest.labels.isEmpty && cached.commenters.isEmpty)
        #expect(cached.pullRequest.mergeable == .unknown)
    }
}
