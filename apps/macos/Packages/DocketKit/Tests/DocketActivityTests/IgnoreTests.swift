import DocketActivity
import DocketCore
import DocketTestSupport
import Foundation
import Testing

struct IgnoreTests {
    @Test("Worked example #31: a re-request does not end an ignore")
    func example31() {
        var timeline = Timeline()
        timeline.poll([])
        timeline.advance(60)
        let pullRequest = Fixtures.pullRequest(requests: [.user(login: "you")])
        var detail = PullRequestDetail(id: pullRequest.id, requestEvents: [Fixtures.request("E1", at: timeline.now)])
        timeline.poll([pullRequest], [detail])
        timeline.config.ignored[pullRequest.id] = Config.IgnoreEntry(ref: pullRequest.ref, ignoredAt: timeline.now)
        timeline.advance(2 * 3600)
        detail.requestEvents.append(Fixtures.request("E2", at: timeline.now))
        let output = timeline.poll([pullRequest], [detail])
        #expect(output.notifications.isEmpty)
        #expect(output.state.reminders.isEmpty)
        let items = Watch.items(cache: output.cache.pullRequests, config: timeline.config, state: output.state)
        #expect(Count.count(items) == 0)
        #expect(Sections(items).ignored.map(\.id) == [pullRequest.id])
        #expect(Sections(items).reviewRequested.isEmpty)
    }

    @Test("Worked example #32: stopping an ignore notifies nothing that happened meanwhile")
    func example32() {
        var timeline = Timeline()
        let pullRequest = Fixtures.pullRequest(requests: [.user(login: "you")])
        var detail = PullRequestDetail(id: pullRequest.id, requestEvents: [Fixtures.request("E1", at: timeline.now)])
        timeline.poll([pullRequest], [detail])
        timeline.config.ignored[pullRequest.id] = Config.IgnoreEntry(ref: pullRequest.ref, ignoredAt: timeline.now)
        let question = Fixtures.threadComment("TC0", by: "you", at: timeline.now)
        detail.threads = [ReviewThread(id: "T0", comments: [question])]
        for day in 1...2 {
            timeline.advance(86400)
            detail.threads[0].comments.append(Fixtures.threadComment("TC\(day)", by: "ana", at: timeline.now))
            #expect(timeline.poll([pullRequest], [detail]).notifications.isEmpty)
        }
        timeline.config.ignored[pullRequest.id] = nil
        timeline.advance(60)
        let output = timeline.poll([pullRequest], [detail])
        #expect(output.notifications.allSatisfy { if case .reminders = $0.content { true } else { false } })
        let items = Watch.items(cache: output.cache.pullRequests, config: timeline.config, state: output.state)
        #expect(Count.count(items) == 1)
        #expect(Sections(items).reviewRequested.first?.items.map(\.id) == [pullRequest.id])
    }
}
