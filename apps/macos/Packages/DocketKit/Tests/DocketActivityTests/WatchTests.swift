import DocketActivity
import DocketCore
import DocketTestSupport
import Foundation
import Testing

struct WatchTests {
    private let now = Fixtures.now

    @Test(arguments: [(0, nil), (1, "1"), (99, "99"), (100, "99+")] as [(Int, String?)])
    func countLabels(count: Int, expected: String?) {
        #expect(Count.label(count) == expected)
    }

    @Test func countHalvesCanBeTurnedOff() {
        let requested = WatchedPullRequest(
            pullRequest: Fixtures.pullRequest(), role: .reviewRequested, status: .noReviewers)
        let blocked = WatchedPullRequest(
            pullRequest: Fixtures.pullRequest("PR_2", author: "you"), role: .authored, status: .conflict)
        let waiting = WatchedPullRequest(
            pullRequest: Fixtures.pullRequest("PR_3", author: "you"), role: .authored, status: .waitingForReview)
        var ignored = requested
        ignored.ignoredAt = now
        #expect(Count.count([requested, blocked, waiting, ignored]) == 2)
        #expect(Count.count([requested, blocked], settings: Config.Count(includeReviewRequests: false)) == 1)
        #expect(Count.count([requested, blocked], settings: Config.Count(includeBlockedAuthored: false)) == 1)
    }

    @Test func reviewersListPendingThenDecisionsThenCommenters() {
        let pullRequest = Fixtures.pullRequest(
            author: "you",
            requests: [.user(login: "ana"), .team(organization: "acme", slug: "backend"), .user(login: "carla")],
            latestReviews: [
                LatestReview(login: "bruno", state: .approved), LatestReview(login: "carla", state: .changesRequested),
            ]
        )
        let entries = Reviewers.entries(for: pullRequest, commenters: ["dave", "bruno"])
        #expect(
            entries == [
                ReviewerEntry(handle: "@ana", state: .pending),
                ReviewerEntry(handle: "@acme/backend", state: .pending),
                ReviewerEntry(handle: "@bruno", state: .approved),
                ReviewerEntry(handle: "@carla", state: .changesRequested, reRequested: true),
                ReviewerEntry(handle: "@dave", state: .commented),
            ])
    }

    @Test func commentersAreReviewersWhoOnlyCommented() {
        let pullRequest = Fixtures.pullRequest(author: "you")
        let detail = PullRequestDetail(
            id: pullRequest.id,
            reviews: [
                Fixtures.review("R1", by: "dave", .commented, at: now),
                Fixtures.review("R2", by: "bruno", .commented, at: now),
                Fixtures.review("R3", by: "bruno", .approved, at: now),
                Fixtures.review("R4", by: "you", .commented, at: now),
            ])
        #expect(
            Reviewers.commenters(in: detail, pullRequest: pullRequest, viewer: ViewerContext(login: "you")) == ["dave"])
    }

    @Test func itemsApplyTheSelectionTagsMutesAndMarks() {
        let api = CachedPullRequest(pullRequest: Fixtures.pullRequest("PR_1"), role: .reviewRequested)
        let legacy = CachedPullRequest(
            pullRequest: Fixtures.pullRequest("PR_2", repository: "acme/legacy"), role: .reviewRequested)
        let mine = CachedPullRequest(
            pullRequest: Fixtures.pullRequest("PR_3", author: "you", mergeable: .unknown), role: .authored)
        var config = Config(selection: Selection(excludedRepositories: ["acme/legacy"]))
        config.tags["PR_1"] = Config.TagEntry(ref: "acme/api#482", tags: ["wip"], updatedAt: now)
        config.mutes["PR_1"] = Config.MuteEntry(ref: "acme/api#482", scope: .all, mutedAt: now)
        config.mutes["PR_3"] = Config.MuteEntry(ref: "acme/api#482", scope: .all, mutedAt: now)
        config.ignored["PR_3"] = Config.IgnoreEntry(ref: "acme/api#482", ignoredAt: now)
        let state = PersistedState(
            cursors: [
                "PR_3": Cursor(ref: "", role: .authored, updatedAt: now, enteredAt: now, lastMergeable: .conflicting)
            ],
            marked: ["PR_1", "PR_3"])
        let items = Watch.items(cache: [api, legacy, mine], config: config, state: state, now: Fixtures.now)
        #expect(items.map(\.id) == ["PR_1", "PR_3"])
        #expect(items[0].tags == ["wip"])
        #expect(items[0].mute == .all)
        #expect(items[0].isMarked)
        #expect(items[1].status == .conflict)
        #expect(items[1].isIgnored)
        #expect(items[1].mute == nil)
        #expect(!items[1].isMarked)
    }

    @Test func sectionsFollowTheDesignOrder() {
        func requested(_ id: String, _ repository: String, _ number: Int, waited hours: Double) -> WatchedPullRequest {
            WatchedPullRequest(
                pullRequest: Fixtures.pullRequest(id, number: number, repository: repository),
                role: .reviewRequested, status: .waitingForReview,
                request: RequestInfo(requestedAt: now.addingTimeInterval(-Fixtures.hours(hours)), requestedBy: "ana"))
        }
        func mine(_ id: String, _ status: Status, ageDays: Double) -> WatchedPullRequest {
            WatchedPullRequest(
                pullRequest: Fixtures.pullRequest(
                    id, author: "you", createdAt: now.addingTimeInterval(-Fixtures.days(ageDays))),
                role: .authored, status: status)
        }
        func involved(_ id: String, updated hours: Double) -> WatchedPullRequest {
            WatchedPullRequest(
                pullRequest: Fixtures.pullRequest(id, updatedAt: now.addingTimeInterval(-Fixtures.hours(hours))),
                role: .involved, status: .waitingForReview)
        }
        var ignored = involved("I1", updated: 1)
        ignored.ignoredAt = now
        let items = [
            requested("R1", "acme/web", 1, waited: 10), requested("R2", "acme/api", 2, waited: 5),
            requested("R3", "acme/api", 3, waited: 20), requested("R4", "acme/web", 4, waited: 1),
            mine("M1", .waitingForReview, ageDays: 9), mine("M2", .conflict, ageDays: 1),
            mine("M3", .conflict, ageDays: 3), involved("V1", updated: 5), involved("V2", updated: 1), ignored,
        ]
        let sections = Sections(items)
        #expect(sections.reviewRequested.map(\.repository) == ["acme/web", "acme/api"])
        #expect(sections.reviewRequested[0].items.map(\.id) == ["R4", "R1"])
        #expect(sections.reviewRequested[1].items.map(\.id) == ["R2", "R3"])
        #expect(sections.reviewRequestedCount == 4)
        #expect(sections.mine.map(\.id) == ["M2", "M3", "M1"])
        #expect(sections.involved.map(\.id) == ["V2", "V1"])
        #expect(sections.ignored.map(\.id) == ["I1"])

        var tagged = items[4]
        tagged.tags = ["wip"]
        #expect(Sections([tagged, items[5]], tag: "wip").mine.map(\.id) == ["M1"])
        #expect(Sections(items, repository: "ACME/web").reviewRequested.map(\.repository) == ["acme/web"])
    }
}
