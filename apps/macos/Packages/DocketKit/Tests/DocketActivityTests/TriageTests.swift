import DocketActivity
import DocketCore
import DocketTestSupport
import Foundation
import Testing

struct TriageTests {
    private let now = Fixtures.now
    private let day = Fixtures.days(1)

    private func cached(
        author: String = "ana", isBot: Bool = false, createdDaysAgo: Double, activity: [ActivityStamp] = []
    ) -> CachedPullRequest {
        let pullRequest = Fixtures.pullRequest(
            author: author, createdAt: now.addingTimeInterval(-createdDaysAgo * day), authorIsBot: isBot)
        return CachedPullRequest(pullRequest: pullRequest, role: .reviewRequested, activity: activity)
    }

    @Test func humansBotsAndStale() {
        #expect(Triage.of(cached(createdDaysAgo: 1), config: Config(), now: now) == .humans)
        #expect(Triage.of(cached(author: "dependabot[bot]", createdDaysAgo: 1), config: Config(), now: now) == .bots)
        #expect(Triage.of(cached(createdDaysAgo: 8), config: Config(), now: now) == .stale)
        let config = Config(triage: Config.Triage(staleAfterDays: 14, extraBotLogins: ["ana"]))
        #expect(Triage.of(cached(createdDaysAgo: 8), config: config, now: now) == .bots)
    }

    @Test func staleWinsOverBots() {
        #expect(
            Triage.of(cached(author: "renovate", isBot: true, createdDaysAgo: 30), config: Config(), now: now) == .stale
        )
    }

    @Test func freshRequestOnOldPullRequestIsNotStale() {
        let entry = cached(
            createdDaysAgo: 30, activity: [ActivityStamp(login: "ana", at: now.addingTimeInterval(-Fixtures.hours(1)))])
        #expect(Triage.of(entry, config: Config(), now: now) == .humans)
        let botOnly = cached(
            createdDaysAgo: 30, activity: [ActivityStamp(login: "ci", isBot: true, at: now)])
        #expect(Triage.of(botOnly, config: Config(), now: now) == .stale)
    }

    @Test func staleExcludedFromCountByDefaultBotsCount() {
        let entries = [
            cached(createdDaysAgo: 1), cached(author: "renovate[bot]", createdDaysAgo: 1), cached(createdDaysAgo: 9),
        ].enumerated().map { index, entry in
            var copy = entry
            copy.pullRequest.id = "PR_\(index)"
            return copy
        }
        let state = PersistedState()
        #expect(Count.count(Watch.items(cache: entries, config: Config(), state: state, now: now)) == 2)
        let quiet = Config(triage: Config.Triage(countBots: false))
        #expect(
            Count.count(Watch.items(cache: entries, config: quiet, state: state, now: now), triage: quiet.triage) == 1)
        let all = Config(triage: Config.Triage(countStale: true))
        #expect(Count.count(Watch.items(cache: entries, config: all, state: state, now: now), triage: all.triage) == 3)
        #expect(Triage.excluded(entries, config: Config(), now: now) == ["PR_2"])
    }

    @Test func staleRequestDoesNotNotifyOrRemind() {
        var timeline = Timeline()
        timeline.poll([])
        timeline.advance(Fixtures.hours(1))
        let old = Fixtures.pullRequest(
            createdAt: timeline.now.addingTimeInterval(-20 * day), requests: [.user(login: "you")])
        // The request comes from a bot account listed as a bot, so it is not human activity either.
        var config = Config(triage: Config.Triage(extraBotLogins: ["ana"]))
        config.reminders.intervalMinutes = 15
        timeline.config = config
        let output = timeline.poll(
            [old], [PullRequestDetail(id: old.id, requestEvents: [Fixtures.request("E1", at: timeline.now)])])
        #expect(output.notifications.isEmpty)
        timeline.advance(Fixtures.hours(2))
        let quiet = timeline.poll([old])
        #expect(quiet.notifications.isEmpty)
        #expect(quiet.state.reminders.isEmpty)
        timeline.config.triage.countStale = true
        timeline.advance(Fixtures.hours(2))
        // Counted again: tracked for reminders from now, without a burst for the time it was left out.
        let counted = timeline.poll([old])
        #expect(counted.notifications.isEmpty)
        #expect(counted.state.reminders[old.id] != nil)
    }

    @Test func manyRequestsStillCapped() {
        var timeline = Timeline()
        timeline.poll([])
        timeline.advance(Fixtures.hours(1))
        let requests = (0..<7).map { index in
            Fixtures.pullRequest(
                "PR_\(index)", number: 300 + index, repository: "acme/r\(index % 5)", requests: [.user(login: "you")])
        }
        let details = requests.enumerated().map { index, pullRequest in
            PullRequestDetail(
                id: pullRequest.id,
                requestEvents: [Fixtures.request("E\(index)", at: timeline.now.addingTimeInterval(Double(-index)))])
        }
        let output = timeline.poll(requests, details)
        #expect(output.notifications.count == 5)
        #expect(output.notifications.prefix(4).allSatisfy { $0.events.count == 1 })
        #expect(output.notifications.last?.content == .overflow(updates: 3, repositories: 3))
    }
}
