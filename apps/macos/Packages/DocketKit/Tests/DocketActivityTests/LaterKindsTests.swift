import DocketActivity
import DocketCore
import DocketTestSupport
import Foundation
import Testing

struct LaterKindsTests {
    private func kinds(_ output: PollOutput) -> [EventKind?] { output.notifications.map(\.kind) }

    @Test("Worked example #37: failing checks notify once per head commit")
    func example37() {
        var timeline = Timeline()
        var mine = Fixtures.pullRequest(number: 470, author: "you", checks: .success, head: "a0")
        timeline.poll([mine], [PullRequestDetail(id: mine.id)])
        timeline.advance(60)
        mine.checks = .failure
        mine.headOID = "a1"
        #expect(kinds(timeline.poll([mine])) == [.checksFailed])
        timeline.advance(60)
        #expect(timeline.poll([mine]).notifications.isEmpty)
        timeline.advance(60)
        mine.headOID = "a2"
        #expect(kinds(timeline.poll([mine])) == [.checksFailed])
    }

    @Test("Worked example #38: a pull request already failing when first seen does not notify")
    func example38() {
        var timeline = Timeline()
        timeline.poll([])
        timeline.advance(60)
        let mine = Fixtures.pullRequest(number: 470, author: "you", checks: .failure, head: "a1")
        #expect(timeline.poll([mine], [PullRequestDetail(id: mine.id)]).notifications.isEmpty)
        timeline.advance(60)
        #expect(timeline.poll([mine]).notifications.isEmpty)
    }

    @Test("Worked example #39: merged by someone else notifies; merged by you does not")
    func example39() {
        var timeline = Timeline()
        var theirs = Fixtures.pullRequest("PR_1", number: 470, author: "you")
        var yours = Fixtures.pullRequest("PR_2", number: 471, author: "you")
        timeline.poll([theirs, yours], [PullRequestDetail(id: "PR_1"), PullRequestDetail(id: "PR_2")])
        timeline.advance(60)
        theirs.state = .merged
        theirs.mergedBy = "bruno"
        yours.state = .merged
        yours.mergedBy = "you"
        let output = timeline.poll([theirs, yours], [PullRequestDetail(id: "PR_1"), PullRequestDetail(id: "PR_2")])
        #expect(kinds(output) == [.closedByOther])
        #expect(output.notifications.first?.events.first?.merged == true)
        #expect(output.notifications.first?.events.first?.actor == "bruno")
        #expect(output.state.cursors["PR_1"]?.role == nil)
        #expect(output.cache.pullRequests.isEmpty)
    }

    @Test func closedWithoutMergeNamesTheCloser() {
        var timeline = Timeline()
        var mine = Fixtures.pullRequest(author: "you")
        timeline.poll([mine], [PullRequestDetail(id: mine.id)])
        timeline.advance(60)
        mine.state = .closed
        #expect(
            PollEngine.detailIDs(
                summaries: [mine], discovery: Discovery(), state: timeline.state, viewer: timeline.viewer,
                now: timeline.now) == [mine.id])
        let output = timeline.poll([mine], [PullRequestDetail(id: mine.id, closedBy: "carla")])
        #expect(output.notifications.first?.events.first?.merged == false)
        #expect(output.notifications.first?.events.first?.actor == "carla")
    }

    @Test("Worked example #40: a mention on someone else's pull request fires")
    func example40() {
        var timeline = Timeline()
        let theirs = Fixtures.pullRequest(number: 88, repository: "acme/web", author: "carla")
        timeline.poll([theirs], [PullRequestDetail(id: theirs.id)], involved: [theirs.id])
        timeline.advance(60)
        var comment = Fixtures.comment("C1", by: "carla", at: timeline.now)
        comment.mentions = Mentions.logins(in: "@you can you check the migration?")
        let output = timeline.poll(
            [theirs], [PullRequestDetail(id: theirs.id, comments: [comment])], involved: [theirs.id])
        #expect(kinds(output) == [.mention])
    }

    @Test("Worked example #41: a mention replaces the comment")
    func example41() {
        var timeline = Timeline()
        let mine = Fixtures.pullRequest(number: 470, author: "you")
        timeline.poll([mine], [PullRequestDetail(id: mine.id)])
        timeline.advance(60)
        var comment = Fixtures.comment("C1", by: "dave", at: timeline.now)
        comment.mentions = Mentions.logins(in: "ping @you")
        #expect(kinds(timeline.poll([mine], [PullRequestDetail(id: mine.id, comments: [comment])])) == [.mention])
    }

    @Test("Worked example #42: a team or a longer login is not you")
    func example42() {
        #expect(Mentions.logins(in: "@acme/backend please look") == [])
        #expect(Mentions.logins(in: "cc @youngster") == ["youngster"])
        #expect(Mentions.logins(in: "mail you@example.com") == [])
        #expect(Mentions.logins(in: "@you, @ana and @you") == ["you", "ana"])
        var timeline = Timeline()
        let mine = Fixtures.pullRequest(number: 470, author: "you")
        timeline.poll([mine], [PullRequestDetail(id: mine.id)])
        timeline.advance(60)
        var comment = Fixtures.comment("C1", by: "dave", at: timeline.now)
        comment.mentions = Mentions.logins(in: "@acme/backend please look, @youngster")
        #expect(kinds(timeline.poll([mine], [PullRequestDetail(id: mine.id, comments: [comment])])) == [.commentAdded])
    }

    @Test func aMentionInAReplyIsAMention() {
        var timeline = Timeline()
        let theirs = Fixtures.pullRequest(number: 88, repository: "acme/web", author: "carla")
        let question = Fixtures.threadComment("TC0", by: "you", at: timeline.now)
        timeline.poll(
            [theirs], [PullRequestDetail(id: theirs.id, threads: [ReviewThread(id: "T0", comments: [question])])],
            involved: [theirs.id])
        timeline.advance(60)
        var reply = Fixtures.threadComment("TC1", by: "carla", at: timeline.now)
        reply.mentions = ["you"]
        let output = timeline.poll(
            [theirs],
            [PullRequestDetail(id: theirs.id, threads: [ReviewThread(id: "T0", comments: [question, reply])])],
            involved: [theirs.id])
        #expect(kinds(output) == [.mention])
    }
}
