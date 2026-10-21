import DocketActivity
import DocketCore
import DocketTestSupport
import Foundation
import Testing

struct EventTests {
    private let minute: TimeInterval = 60
    private let hour: TimeInterval = 3600

    @Test("Worked example #2: what happened while Docket was closed notifies")
    func example2() {
        var timeline = Timeline()
        timeline.poll([])
        timeline.advance(2 * hour)
        let requested = Fixtures.pullRequest(requests: [.user(login: "you")])
        let output = timeline.poll(
            [requested],
            [
                PullRequestDetail(
                    id: requested.id,
                    requestEvents: [Fixtures.request("E1", at: timeline.now.addingTimeInterval(-hour))])
            ])
        #expect(output.notifications.count == 1)
        #expect(output.notifications.first?.kind == .reviewRequested)
        #expect(output.notifications.first?.events.first?.actor == "ana")
    }

    @Test("Worked example #3: a re-request after you reviewed notifies")
    func example3() {
        var timeline = Timeline()
        let t0 = timeline.now
        let first = Fixtures.request("E1", at: t0.addingTimeInterval(-hour))
        var pullRequest = Fixtures.pullRequest(requests: [.user(login: "you")])
        timeline.poll([pullRequest], [PullRequestDetail(id: pullRequest.id, requestEvents: [first])])
        timeline.advance(10 * minute)
        pullRequest.reviewRequests = []
        let review = Fixtures.review("R1", by: "you", .approved, at: timeline.now.addingTimeInterval(-minute))
        timeline.poll(
            [pullRequest], [PullRequestDetail(id: pullRequest.id, reviews: [review], requestEvents: [first])],
            involved: [pullRequest.id])
        #expect(timeline.state.cursors[pullRequest.id]?.role == .involved)
        timeline.advance(10 * minute)
        pullRequest.reviewRequests = [.user(login: "you")]
        let again = Fixtures.request("E2", at: timeline.now.addingTimeInterval(-minute))
        let output = timeline.poll(
            [pullRequest], [PullRequestDetail(id: pullRequest.id, reviews: [review], requestEvents: [first, again])])
        #expect(output.notifications.map(\.kind) == [.reviewRequested])
        #expect(output.notifications.first?.events.map(\.id) == ["reviewRequested:E2"])
    }

    @Test("Worked example #4: a request withdrawn before the poll never notifies")
    func example4() {
        var timeline = Timeline()
        timeline.poll([])
        timeline.advance(minute)
        let withdrawn = Fixtures.pullRequest()
        let output = timeline.poll(
            [withdrawn],
            [
                PullRequestDetail(
                    id: withdrawn.id, requestEvents: [Fixtures.request("E1", at: timeline.now.addingTimeInterval(-30))])
            ])
        #expect(output.notifications.isEmpty)
    }

    @Test("Worked example #5: an approval with inline comments is one notification")
    func example5() {
        var timeline = Timeline()
        let mine = Fixtures.pullRequest(number: 470, author: "you")
        let mineThread = Fixtures.threadComment("TC0", by: "you", at: timeline.now.addingTimeInterval(-hour))
        timeline.poll(
            [mine], [PullRequestDetail(id: mine.id, threads: [ReviewThread(id: "T0", comments: [mineThread])])])
        timeline.advance(minute)
        let at = timeline.now.addingTimeInterval(-10)
        let detail = PullRequestDetail(
            id: mine.id,
            reviews: [Fixtures.review("R1", by: "ana", .approved, at: at)],
            threads: [
                ReviewThread(
                    id: "T0", comments: [mineThread, Fixtures.threadComment("TC1", by: "ana", at: at, review: "R1")]),
                ReviewThread(id: "T2", comments: [Fixtures.threadComment("TC2", by: "ana", at: at, review: "R1")]),
                ReviewThread(id: "T3", comments: [Fixtures.threadComment("TC3", by: "ana", at: at, review: "R1")]),
            ])
        let output = timeline.poll([mine], [detail])
        #expect(output.notifications.count == 1)
        #expect(output.notifications.first?.kind == .reviewSubmitted)
        #expect(output.notifications.first?.events.first?.decision == .approved)
    }

    @Test("Worked example #6: a reply-only review is a reply, not a review")
    func example6() {
        var timeline = Timeline()
        let mine = Fixtures.pullRequest(number: 470, author: "you")
        let question = Fixtures.threadComment("TC0", by: "you", at: timeline.now.addingTimeInterval(-hour))
        timeline.poll([mine], [PullRequestDetail(id: mine.id, threads: [ReviewThread(id: "T0", comments: [question])])])
        timeline.advance(minute)
        let at = timeline.now.addingTimeInterval(-10)
        let detail = PullRequestDetail(
            id: mine.id, reviews: [Fixtures.review("R1", by: "bruno", .commented, at: at, bodyIsEmpty: true)],
            threads: [
                ReviewThread(
                    id: "T0", comments: [question, Fixtures.threadComment("TC1", by: "bruno", at: at, review: "R1")])
            ])
        let output = timeline.poll([mine], [detail])
        #expect(output.notifications.map(\.kind) == [.threadReply])
        #expect(output.notifications.first?.events.first?.actor == "bruno")
    }

    @Test("Worked example #7: on someone else's pull request only replies to you fire")
    func example7() {
        var timeline = Timeline()
        let theirs = Fixtures.pullRequest(number: 88, repository: "acme/web", author: "carla")
        let mine = Fixtures.threadComment("TC0", by: "you", at: timeline.now.addingTimeInterval(-hour))
        timeline.poll(
            [theirs], [PullRequestDetail(id: theirs.id, threads: [ReviewThread(id: "T0", comments: [mine])])],
            involved: [theirs.id])
        timeline.advance(minute)
        let at = timeline.now.addingTimeInterval(-10)
        let detail = PullRequestDetail(
            id: theirs.id, comments: [Fixtures.comment("C1", by: "dave", at: at)],
            threads: [ReviewThread(id: "T0", comments: [mine, Fixtures.threadComment("TC1", by: "carla", at: at)])])
        let output = timeline.poll([theirs], [detail], involved: [theirs.id])
        #expect(output.notifications.map(\.kind) == [.threadReply])
        #expect(output.notifications.first?.events.map(\.actor) == ["carla"])
    }

    @Test("Worked example #8: you and bots never notify")
    func example8() {
        var timeline = Timeline()
        let mine = Fixtures.pullRequest(author: "you")
        timeline.poll([mine], [PullRequestDetail(id: mine.id)])
        timeline.advance(minute)
        let at = timeline.now.addingTimeInterval(-10)
        let detail = PullRequestDetail(
            id: mine.id,
            comments: [
                Fixtures.comment("C1", by: "you", at: at), Fixtures.comment("C2", by: "dependabot[bot]", at: at),
            ])
        #expect(timeline.poll([mine], [detail]).notifications.isEmpty)
    }

    @Test("Worked example #9: an allowlisted bot notifies")
    func example9() {
        var timeline = Timeline()
        timeline.config.botAllowlist = ["copilot-pull-request-reviewer"]
        let mine = Fixtures.pullRequest(author: "you")
        timeline.poll([mine], [PullRequestDetail(id: mine.id)])
        timeline.advance(minute)
        let review = Fixtures.review(
            "R1", by: "copilot-pull-request-reviewer", .commented, at: timeline.now.addingTimeInterval(-10), isBot: true
        )
        let output = timeline.poll([mine], [PullRequestDetail(id: mine.id, reviews: [review])])
        #expect(output.notifications.map(\.kind) == [.reviewSubmitted])
    }

    @Test("Worked example #10: after a night asleep the cap holds and requests come first")
    func example10() {
        var timeline = Timeline()
        let mine = ["acme/mobile", "acme/cli"].enumerated().map { index, repository in
            Fixtures.pullRequest("PR_M\(index)", number: 200 + index, repository: repository, author: "you")
        }
        timeline.poll(mine, mine.map { PullRequestDetail(id: $0.id) })
        timeline.advance(10 * hour)
        let repositories = ["acme/api", "acme/web", "acme/infra", "acme/docs"]
        var pullRequests: [PullRequest] = []
        var details: [PullRequestDetail] = []
        for index in 0..<12 {
            let pullRequest = Fixtures.pullRequest(
                "PR_R\(index)", number: 100 + index, repository: repositories[index % 4],
                requests: [.user(login: "you")])
            pullRequests.append(pullRequest)
            details.append(
                PullRequestDetail(
                    id: pullRequest.id,
                    requestEvents: [Fixtures.request("E\(index)", at: timeline.now.addingTimeInterval(-hour))]))
        }
        for (index, pullRequest) in mine.enumerated() {
            var changed = pullRequest
            changed.updatedAt = timeline.now
            pullRequests.append(changed)
            details.append(
                PullRequestDetail(
                    id: pullRequest.id,
                    reviews: [
                        Fixtures.review(
                            "RV\(index)", by: "bruno", .approved, at: timeline.now.addingTimeInterval(-hour))
                    ]))
        }
        let output = timeline.poll(pullRequests, details)
        #expect(output.notifications.count == 5)
        #expect(output.notifications.prefix(4).allSatisfy { $0.kind == .reviewRequested })
        #expect(output.notifications.last?.content == .overflow(updates: 2, repositories: 2))
        #expect(Set(output.state.delivered.keys).isSuperset(of: ["reviewSubmitted:RV0", "reviewSubmitted:RV1"]))
    }

    @Test("Worked example #16: a commit that is not followed by delivery is not delivered again, and the row is marked")
    func example16() {
        var timeline = Timeline()
        let mine = Fixtures.pullRequest(author: "you")
        timeline.poll([mine], [PullRequestDetail(id: mine.id)])
        timeline.advance(minute)
        let detail = PullRequestDetail(
            id: mine.id, comments: [Fixtures.comment("C1", by: "dave", at: timeline.now.addingTimeInterval(-10))])
        let committed = timeline.poll([mine], [detail])
        #expect(committed.notifications.count == 1)
        // The app died here: the state above is on disk, the notification never reached macOS.
        timeline.advance(minute)
        let relaunched = timeline.poll([mine], [detail])
        #expect(relaunched.notifications.isEmpty)
        #expect(relaunched.state.marked == [mine.id])
    }

    @Test("Worked example #18: re-including a repository does not notify old comments")
    func example18() {
        var timeline = Timeline()
        let theirs = Fixtures.pullRequest(author: "you")
        timeline.poll([theirs], [PullRequestDetail(id: theirs.id)])
        timeline.config.selection.excludedRepositories = ["acme/api"]
        timeline.advance(hour)
        let old = [
            Fixtures.comment("C1", by: "dave", at: timeline.now), Fixtures.comment("C2", by: "ana", at: timeline.now),
        ]
        timeline.poll([theirs], [PullRequestDetail(id: theirs.id, comments: old)])
        timeline.config.selection.excludedRepositories = []
        timeline.advance(3 * 86400)
        let output = timeline.poll([theirs], [PullRequestDetail(id: theirs.id, comments: old)])
        #expect(output.notifications.isEmpty)
        #expect(output.cache.pullRequests.count == 1)
    }

    @Test func aKindTurnedOffDoesNotNotifyButStillMarks() {
        var timeline = Timeline()
        timeline.config.notifications.commentAdded = false
        let mine = Fixtures.pullRequest(author: "you")
        timeline.poll([mine], [PullRequestDetail(id: mine.id)])
        timeline.advance(minute)
        let output = timeline.poll(
            [mine], [PullRequestDetail(id: mine.id, comments: [Fixtures.comment("C1", by: "dave", at: timeline.now)])])
        #expect(output.notifications.isEmpty)
        #expect(output.state.marked == [mine.id])
    }

    @Test func mutedAllAndIgnoredDoNotNotify() {
        for setup in [0, 1] {
            var timeline = Timeline()
            let mine = Fixtures.pullRequest(author: "you")
            if setup == 0 {
                timeline.config.mutes[mine.id] = Config.MuteEntry(ref: mine.ref, scope: .all, mutedAt: timeline.now)
            } else {
                timeline.config.ignored[mine.id] = Config.IgnoreEntry(ref: mine.ref, ignoredAt: timeline.now)
            }
            timeline.poll([mine], [PullRequestDetail(id: mine.id)])
            timeline.advance(minute)
            let output = timeline.poll(
                [mine],
                [PullRequestDetail(id: mine.id, comments: [Fixtures.comment("C1", by: "dave", at: timeline.now)])])
            #expect(output.notifications.isEmpty)
        }
    }

    @Test func coalescingGroupsByRepositoryAndKindOldestFirst() {
        var timeline = Timeline()
        let api = (0..<3).map { Fixtures.pullRequest("PR_\($0)", number: 480 + $0, requests: [.user(login: "you")]) }
        let web = Fixtures.pullRequest("PR_W", number: 88, repository: "acme/web", requests: [.user(login: "you")])
        timeline.poll([])
        timeline.advance(hour)
        let details = (api + [web]).enumerated().map { index, pullRequest in
            PullRequestDetail(
                id: pullRequest.id,
                requestEvents: [
                    Fixtures.request("E\(index)", at: timeline.now.addingTimeInterval(-Double(10 - index) * 60))
                ])
        }
        let output = timeline.poll(api + [web], details)
        #expect(output.notifications.count == 2)
        let apiGroup = output.notifications.first { $0.repository == "acme/api" }
        #expect(apiGroup?.events.map(\.number) == [480, 481, 482])
        #expect(output.notifications.allSatisfy { $0.kind == .reviewRequested })
    }

    @Test func oneReviewerSeveralReviewsFoldIntoTheLatest() {
        var timeline = Timeline()
        let mine = Fixtures.pullRequest(author: "you")
        timeline.poll([mine], [PullRequestDetail(id: mine.id)])
        timeline.advance(minute)
        let reviews = [
            Fixtures.review("R1", by: "carla", .commented, at: timeline.now.addingTimeInterval(-30)),
            Fixtures.review("R2", by: "carla", .approved, at: timeline.now.addingTimeInterval(-10)),
        ]
        let output = timeline.poll([mine], [PullRequestDetail(id: mine.id, reviews: reviews)])
        #expect(output.notifications.first?.events.map(\.id) == ["reviewSubmitted:R2"])
    }

    @Test func theLedgerExpiresAfterFourteenDays() {
        var timeline = Timeline()
        timeline.state.delivered = ["old": timeline.now.addingTimeInterval(-15 * 86400), "recent": timeline.now]
        timeline.state.baselineAt = timeline.now
        let output = timeline.poll([])
        #expect(output.state.delivered.keys.sorted() == ["recent"])
    }
}
