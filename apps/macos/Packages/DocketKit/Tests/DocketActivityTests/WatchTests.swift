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

    @Test func itemsApplyTheSelectionMutesAndMarks() {
        let api = CachedPullRequest(pullRequest: Fixtures.pullRequest("PR_1"), role: .reviewRequested)
        let legacy = CachedPullRequest(
            pullRequest: Fixtures.pullRequest("PR_2", repository: "acme/legacy"), role: .reviewRequested)
        let mine = CachedPullRequest(
            pullRequest: Fixtures.pullRequest("PR_3", author: "you", mergeable: .unknown), role: .authored)
        var config = Config(selection: Selection(excludedRepositories: ["acme/legacy"]))
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
        #expect(items[0].mute == .all)
        #expect(items[0].isMarked)
        #expect(items[1].status == .conflict)
        #expect(items[1].isIgnored)
        #expect(items[1].mute == nil)
        #expect(!items[1].isMarked)
    }

    @Test func lastActivityIsTheLatestHumanCommitPushOrComment() {
        var pullRequest = Fixtures.pullRequest("PR_1", author: "you")
        pullRequest.headCommit = CommitStamp(login: "you", at: now.addingTimeInterval(-Fixtures.hours(3)))
        pullRequest.lastForcePush = ActivityStamp(
            login: "renovate[bot]", isBot: true, at: now.addingTimeInterval(-Fixtures.hours(1)))
        let cached = CachedPullRequest(
            pullRequest: pullRequest, role: .authored,
            activity: [ActivityStamp(login: "ana", at: now.addingTimeInterval(-Fixtures.hours(5)))])
        let item = Watch.items(cache: [cached], config: Config(), state: PersistedState(), now: now)
        // The bot's rebase an hour ago is not activity; your commit three hours ago is.
        #expect(item.first?.lastActivity == now.addingTimeInterval(-Fixtures.hours(3)))
        let quiet = CachedPullRequest(pullRequest: Fixtures.pullRequest("PR_2"), role: .involved)
        let fallback = Watch.items(cache: [quiet], config: Config(), state: PersistedState(), now: now)
        #expect(fallback.first?.lastActivity == quiet.pullRequest.createdAt)
    }

    @Test func aBoardColumnSplitsByRepositoryInTheOrderOfItsRows() {
        let rows = [("P1", "acme/web"), ("P2", "acme/api"), ("P3", "acme/web"), ("P4", "globex/app")].map {
            WatchedPullRequest(
                pullRequest: Fixtures.pullRequest($0.0, repository: $0.1), role: .authored, status: .noReviewers)
        }
        let groups = Sections.byRepository(rows)
        #expect(groups.map(\.repository) == ["acme/web", "acme/api", "globex/app"])
        #expect(groups.first?.items.map(\.id) == ["P1", "P3"])
        #expect(Sections.byRepository([]).isEmpty)
    }

    @Test func botLinksComeFromBotsOnlyLatestFirst() {
        func link(_ path: String, _ source: String) -> PullRequestLink {
            PullRequestLink(url: Fixtures.url(path), source: source)
        }
        var old = Fixtures.comment("C1", by: "vercel[bot]", at: now.addingTimeInterval(-7200), isBot: true)
        old.links = [link("preview/1", "vercel[bot]"), link("preview/2", "vercel[bot]")]
        var new = Fixtures.comment("C2", by: "deployer", at: now, isBot: false)
        new.links = [link("preview/3", "deployer")]
        var human = Fixtures.comment("C3", by: "ana", at: now)
        human.links = [link("elsewhere", "ana")]
        var again = Fixtures.comment("C4", by: "vercel[bot]", at: now.addingTimeInterval(-60), isBot: true)
        again.links = [link("preview/2", "vercel[bot]")]
        let detail = PullRequestDetail(id: "PR_1", comments: [old, new, human, again])
        #expect(detail.botLinks(extra: ["deployer"]).map(\.url.path) == ["/preview/3", "/preview/2", "/preview/1"])
        #expect(detail.botLinks(extra: []).map(\.url.path) == ["/preview/2", "/preview/1"])
        #expect(detail.botLinks(extra: [], perBot: 1).map(\.url.path) == ["/preview/2"])
    }

    @Test func sectionsFollowTheDesignOrder() {
        func requested(_ id: String, _ repository: String, _ number: Int, waited hours: Double) -> WatchedPullRequest {
            WatchedPullRequest(
                pullRequest: Fixtures.pullRequest(id, number: number, repository: repository),
                role: .reviewRequested, status: .waitingForReview,
                request: RequestInfo(requestedAt: now.addingTimeInterval(-Fixtures.hours(hours)), requestedBy: "ana"))
        }
        func mine(_ id: String, _ status: Status, ageDays: Double, activeHours: Double? = nil) -> WatchedPullRequest {
            WatchedPullRequest(
                pullRequest: Fixtures.pullRequest(
                    id, author: "you", createdAt: now.addingTimeInterval(-Fixtures.days(ageDays))),
                role: .authored, status: status,
                lastActivity: activeHours.map { now.addingTimeInterval(-Fixtures.hours($0)) })
        }
        func involved(_ id: String, updated hours: Double) -> WatchedPullRequest {
            WatchedPullRequest(
                pullRequest: Fixtures.pullRequest(id, updatedAt: now.addingTimeInterval(-Fixtures.hours(hours))),
                role: .involved, status: .waitingForReview,
                lastActivity: now.addingTimeInterval(-Fixtures.hours(hours)))
        }
        var ignored = involved("I1", updated: 1)
        ignored.ignoredAt = now
        let items = [
            requested("R1", "acme/web", 1, waited: 10), requested("R2", "acme/api", 2, waited: 5),
            requested("R3", "acme/api", 3, waited: 20), requested("R4", "acme/web", 4, waited: 1),
            mine("M1", .waitingForReview, ageDays: 9), mine("M2", .conflict, ageDays: 1),
            mine("M3", .checksFailing, ageDays: 3, activeHours: 2), involved("V1", updated: 5),
            involved("V2", updated: 1), ignored,
        ]
        let sections = Sections(items)
        #expect(sections.reviewRequested.map(\.repository) == ["acme/web", "acme/api"])
        #expect(sections.reviewRequested[0].items.map(\.id) == ["R4", "R1"])
        #expect(sections.reviewRequested[1].items.map(\.id) == ["R2", "R3"])
        #expect(sections.reviewRequestedCount == 4)
        // Ready first, then blocked; inside a group the latest activity first, whatever the status: M3 is older
        // but had a commit two hours ago.
        #expect(sections.mine.map(\.id) == ["M1", "M3", "M2"])
        #expect(sections.mineGroups.map(\.kind) == [.ready, .blocked])
        #expect(sections.involved.map(\.id) == ["V2", "V1"])
        #expect(sections.ignored.map(\.id) == ["I1"])

        let web = Sections(items, filter: PopoverFilter(repositories: ["ACME/web"]))
        #expect(web.reviewRequested.map(\.repository) == ["acme/web"])
    }
}
