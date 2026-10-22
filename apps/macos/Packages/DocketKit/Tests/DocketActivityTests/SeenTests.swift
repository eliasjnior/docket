import DocketActivity
import DocketCore
import DocketTestSupport
import Foundation
import Testing

struct SeenTests {
    private let hour = Fixtures.hours(1)

    private func unseen(_ output: PollOutput, _ timeline: Timeline) -> [String: Bool] {
        var state = output.state
        state.viewerLogin = "you"
        let items = Watch.items(
            cache: output.cache.pullRequests, config: timeline.config, state: state, now: timeline.now)
        return Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.isUnseen) })
    }

    @Test func firstRunMarksEverythingSeen() {
        var timeline = Timeline()
        let listed = (0..<3).map { Fixtures.pullRequest("PR_\($0)", number: $0, requests: [.user(login: "you")]) }
        let output = timeline.poll(listed)
        #expect(output.state.seenBaselineAt == timeline.now)
        #expect(unseen(output, timeline).values.allSatisfy { !$0 })
    }

    @Test func newPullRequestAfterBaselineIsUnseen() {
        var timeline = Timeline()
        timeline.poll([])
        timeline.advance(hour)
        let arrived = Fixtures.pullRequest(requests: [.user(login: "you")])
        #expect(unseen(timeline.poll([arrived]), timeline)["PR_1"] == true)
    }

    @Test func humanActivityAfterSeenMakesUnseenButBotsAndYouDoNot() {
        var timeline = Timeline()
        var pullRequest = Fixtures.pullRequest(requests: [.user(login: "you")])
        timeline.poll([pullRequest], [PullRequestDetail(id: pullRequest.id)])
        timeline.advance(hour)

        pullRequest.updatedAt = timeline.now
        let botComment = PullRequestDetail(
            id: pullRequest.id, comments: [Fixtures.comment("C1", by: "ci", at: timeline.now, isBot: true)])
        #expect(unseen(timeline.poll([pullRequest], [botComment]), timeline)["PR_1"] == false)

        timeline.advance(hour)
        pullRequest.updatedAt = timeline.now
        let ownComment = PullRequestDetail(
            id: pullRequest.id,
            comments: [
                Fixtures.comment("C1", by: "ci", at: timeline.now, isBot: true),
                Fixtures.comment("C2", by: "you", at: timeline.now),
            ])
        #expect(unseen(timeline.poll([pullRequest], [ownComment]), timeline)["PR_1"] == false)

        timeline.advance(hour)
        pullRequest.updatedAt = timeline.now
        pullRequest.headCommit = CommitStamp(login: "ana", at: timeline.now)
        #expect(unseen(timeline.poll([pullRequest]), timeline)["PR_1"] == true)
    }

    @Test func openingAgainClearsIt() {
        var timeline = Timeline()
        timeline.poll([])
        timeline.advance(hour)
        var pullRequest = Fixtures.pullRequest(requests: [.user(login: "you")])
        pullRequest.headCommit = CommitStamp(login: "ana", at: timeline.now.addingTimeInterval(-hour))
        let output = timeline.poll([pullRequest])
        #expect(unseen(output, timeline)["PR_1"] == true)
        timeline.state.seen["PR_1"] = timeline.now
        #expect(
            unseen(PollOutput(state: timeline.state, cache: output.cache, notifications: [], events: []), timeline)[
                "PR_1"] == false)
    }

    @Test func ignoredIsNeverUnseen() {
        var timeline = Timeline()
        timeline.poll([])
        timeline.advance(hour)
        timeline.config.ignored["PR_1"] = Config.IgnoreEntry(ref: "acme/api#482", ignoredAt: timeline.now)
        #expect(
            unseen(timeline.poll([Fixtures.pullRequest(requests: [.user(login: "you")])]), timeline)["PR_1"] == false)
    }
}
