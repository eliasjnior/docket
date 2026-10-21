import DocketActivity
import DocketCore
import DocketTestSupport
import Foundation
import Testing

struct FocusHoldTests {
    private let minute: TimeInterval = 60
    private let hour: TimeInterval = 3600

    @Test("Worked example #33: the digest groups kinds per repository and reminders are not queued")
    func example33() {
        var timeline = Timeline()
        let mine = Fixtures.pullRequest("PR_M", number: 88, repository: "acme/web", author: "you")
        let waiting = Fixtures.pullRequest("PR_W", number: 482, requests: [.user(login: "you")])
        let waitingDetail = PullRequestDetail(id: waiting.id, requestEvents: [Fixtures.request("E0", at: timeline.now)])
        timeline.poll([mine, waiting], [PullRequestDetail(id: mine.id), waitingDetail])
        timeline.advance(50 * minute)
        timeline.state.focusHold = FocusHold(since: timeline.now)
        let requests = (1...2).map {
            Fixtures.pullRequest("PR_\($0)", number: 490 + $0, requests: [.user(login: "you")])
        }
        let details =
            requests.map {
                PullRequestDetail(id: $0.id, requestEvents: [Fixtures.request("E\($0.id)", at: timeline.now)])
            }
            + [
                PullRequestDetail(
                    id: mine.id, reviews: [Fixtures.review("R1", by: "bruno", .approved, at: timeline.now)]),
                waitingDetail,
            ]
        timeline.advance(minute)
        var held = timeline.poll(requests + [mine, waiting], details)
        #expect(held.notifications.isEmpty)
        for _ in 0..<70 {
            timeline.advance(minute)
            held = timeline.poll(requests + [mine, waiting], details)
            #expect(held.notifications.isEmpty)
        }
        #expect(held.state.held.count == 3)
        timeline.state.focusHold = nil
        timeline.advance(minute)
        let end = timeline.poll(requests + [mine, waiting], details)
        #expect(end.notifications.count == 2)
        let bodies = end.notifications.compactMap { notification -> (String?, [EventKind])? in
            if case .digest(let events) = notification.content { return (notification.repository, events.map(\.kind)) }
            return nil
        }
        #expect(bodies.first { $0.0 == "acme/api" }?.1 == [.reviewRequested, .reviewRequested])
        #expect(bodies.first { $0.0 == "acme/web" }?.1 == [.reviewSubmitted])
        #expect(end.state.held.isEmpty)
        #expect(timeline.state.reminders["PR_W"] != nil)
    }

    @Test("Worked example #34: a hold survives a relaunch")
    func example34() {
        var timeline = Timeline()
        let mine = Fixtures.pullRequest(author: "you")
        timeline.poll([mine], [PullRequestDetail(id: mine.id)])
        timeline.state.focusHold = FocusHold(since: timeline.now)
        timeline.advance(minute)
        var comments = [Fixtures.comment("C1", by: "dave", at: timeline.now)]
        timeline.poll([mine], [PullRequestDetail(id: mine.id, comments: comments)])
        // Relaunch: the state carries the hold and what it held.
        var relaunched = Timeline()
        relaunched.state = timeline.state
        relaunched.cache = timeline.cache
        relaunched.now = timeline.now.addingTimeInterval(10 * minute)
        comments.append(Fixtures.comment("C2", by: "ana", at: relaunched.now))
        relaunched.poll([mine], [PullRequestDetail(id: mine.id, comments: comments)])
        #expect(relaunched.state.held.map(\.eventID) == ["commentAdded:C1", "commentAdded:C2"])
        relaunched.state.focusHold = nil
        relaunched.advance(minute)
        let end = relaunched.poll([mine], [PullRequestDetail(id: mine.id, comments: comments)])
        #expect(end.notifications.count == 1)
    }

    @Test("Worked example #35: a hold ends by itself after 12 hours")
    func example35() {
        var timeline = Timeline()
        let mine = Fixtures.pullRequest(author: "you")
        timeline.poll([mine], [PullRequestDetail(id: mine.id)])
        timeline.state.focusHold = FocusHold(since: timeline.now)
        timeline.advance(minute)
        let comments = [Fixtures.comment("C1", by: "dave", at: timeline.now)]
        timeline.poll([mine], [PullRequestDetail(id: mine.id, comments: comments)])
        timeline.advance(11 * hour)
        #expect(timeline.poll([mine]).notifications.isEmpty)
        timeline.advance(hour)
        let end = timeline.poll([mine])
        #expect(end.state.focusHold == nil)
        #expect(end.notifications.count == 1)
    }

    @Test("Worked example #36: held events of an ignored pull request are dropped")
    func example36() {
        var timeline = Timeline()
        let mine = Fixtures.pullRequest(author: "you")
        timeline.poll([mine], [PullRequestDetail(id: mine.id)])
        timeline.state.focusHold = FocusHold(since: timeline.now)
        timeline.advance(minute)
        let comments = [
            Fixtures.comment("C1", by: "dave", at: timeline.now), Fixtures.comment("C2", by: "ana", at: timeline.now),
        ]
        timeline.poll([mine], [PullRequestDetail(id: mine.id, comments: comments)])
        timeline.config.ignored[mine.id] = Config.IgnoreEntry(ref: mine.ref, ignoredAt: timeline.now)
        timeline.state.focusHold = nil
        timeline.advance(minute)
        let end = timeline.poll([mine])
        #expect(end.notifications.isEmpty)
        #expect(end.state.held.isEmpty)
    }
}
