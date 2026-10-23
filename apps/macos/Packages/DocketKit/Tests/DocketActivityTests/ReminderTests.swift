import DocketActivity
import DocketCore
import DocketTestSupport
import Foundation
import Testing

struct ReminderTests {
    private let minute: TimeInterval = 60
    private let hour: TimeInterval = 3600

    /// `ana` requests your review on `acme/api#482` at `t0`, after a baseline poll a minute earlier.
    private func requested(at t0: Date? = nil, timeline: inout Timeline) -> (PullRequest, PullRequestDetail) {
        let pullRequest = Fixtures.pullRequest(requests: [.user(login: "you")])
        let detail = PullRequestDetail(
            id: pullRequest.id, requestEvents: [Fixtures.request("E1", at: t0 ?? timeline.now)])
        return (pullRequest, detail)
    }

    private func reminders(_ output: PollOutput) -> [Reminder] {
        output.notifications.flatMap { notification -> [Reminder] in
            if case .reminders(let reminders) = notification.content { return reminders }
            return []
        }
    }

    /// Polls every `step` from now for `duration`, returning the times reminders arrived.
    private func run(
        _ timeline: inout Timeline, _ pullRequest: PullRequest, _ detail: PullRequestDetail, for duration: TimeInterval,
        step: TimeInterval = 60
    ) -> [TimeInterval] {
        let start = timeline.now
        var times: [TimeInterval] = []
        while timeline.now.timeIntervalSince(start) < duration {
            timeline.advance(step)
            if !reminders(timeline.poll([pullRequest], [detail])).isEmpty {
                times.append(timeline.now.timeIntervalSince(start))
            }
        }
        return times
    }

    @Test("Worked example #19: each reminder anchors on the previous one")
    func example19() {
        var timeline = Timeline()
        timeline.poll([])
        timeline.advance(minute)
        let t0 = timeline.now
        let (pullRequest, detail) = requested(timeline: &timeline)
        let first = timeline.poll([pullRequest], [detail])
        #expect(first.notifications.map(\.kind) == [.reviewRequested])
        #expect(reminders(first).isEmpty)
        let times = run(&timeline, pullRequest, detail, for: 3.5 * hour).map { $0 }
        #expect(times == [hour, 2 * hour, 3 * hour])
        #expect(timeline.state.reminders[pullRequest.id]?.requestedAt == t0)
    }

    @Test("Worked example #20: one reminder at wake, never a burst")
    func example20() {
        var timeline = Timeline()
        timeline.poll([])
        timeline.advance(minute)
        let (pullRequest, detail) = requested(timeline: &timeline)
        timeline.poll([pullRequest], [detail])
        timeline.advance(10 * minute)
        timeline.poll([pullRequest], [detail])
        timeline.advance(5 * hour - 10 * minute)
        let wake = timeline.poll([pullRequest], [detail])
        #expect(reminders(wake).count == 1)
        #expect(run(&timeline, pullRequest, detail, for: 1.5 * hour) == [hour])
    }

    @Test("Worked example #21: reviewing ends the role and the reminders")
    func example21() {
        var timeline = Timeline()
        timeline.poll([])
        timeline.advance(minute)
        var (pullRequest, detail) = requested(timeline: &timeline)
        timeline.poll([pullRequest], [detail])
        timeline.advance(40 * minute)
        pullRequest.reviewRequests = []
        detail.reviews = [Fixtures.review("R1", by: "you", .approved, at: timeline.now)]
        timeline.poll([pullRequest], [detail], involved: [pullRequest.id])
        #expect(timeline.state.reminders.isEmpty)
        #expect(run(&timeline, pullRequest, detail, for: 2 * hour).isEmpty)
    }

    @Test("Worked example #22: a re-request starts its own interval")
    func example22() {
        var timeline = Timeline()
        timeline.poll([])
        timeline.advance(minute)
        let start = timeline.now
        var (pullRequest, detail) = requested(timeline: &timeline)
        timeline.poll([pullRequest], [detail])
        timeline.advance(40 * minute)
        pullRequest.reviewRequests = []
        let review = Fixtures.review("R1", by: "you", .commented, at: timeline.now)
        detail.reviews = [review]
        timeline.poll([pullRequest], [detail], involved: [pullRequest.id])
        timeline.advance(80 * minute)
        pullRequest.reviewRequests = [.user(login: "you")]
        detail.requestEvents.append(Fixtures.request("E2", at: timeline.now))
        let again = timeline.poll([pullRequest], [detail])
        #expect(again.notifications.map(\.kind) == [.reviewRequested])
        #expect(timeline.now.timeIntervalSince(start) == 2 * hour)
        #expect(run(&timeline, pullRequest, detail, for: 1.5 * hour) == [hour])
    }

    @Test("Worked example #23: quiet hours across midnight hold the reminder until they end")
    func example23() throws {
        var timeline = Timeline()
        let zone = try #require(TimeZone(identifier: "America/Sao_Paulo"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        timeline.now = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 21, minute: 29)))
        timeline.config.reminders.quietHours = Config.QuietHours(enabled: true, start: "22:00", end: "08:00")
        timeline.poll([])
        timeline.advance(minute)
        let (pullRequest, detail) = requested(timeline: &timeline)
        timeline.poll([pullRequest], [detail])
        let times = run(&timeline, pullRequest, detail, for: 12 * hour, step: 5 * minute)
        // 21:30 + 10 h 30 min = 08:00 the next morning, then 09:00.
        #expect(times == [10.5 * hour, 11.5 * hour])
    }

    @Test("Worked example #24: a fresh install reminds one interval after the install")
    func example24() {
        var timeline = Timeline()
        let (pullRequest, detail) = requested(at: timeline.now.addingTimeInterval(-3 * hour), timeline: &timeline)
        let install = timeline.poll([pullRequest], [detail])
        #expect(install.notifications.isEmpty)
        #expect(run(&timeline, pullRequest, detail, for: 1.5 * hour) == [hour])
    }

    @Test("Worked example #25: muting reminders keeps the other notifications")
    func example25() {
        var timeline = Timeline()
        timeline.poll([])
        timeline.advance(minute)
        var (pullRequest, detail) = requested(timeline: &timeline)
        let question = Fixtures.threadComment("TC0", by: "you", at: timeline.now)
        detail.threads = [ReviewThread(id: "T0", comments: [question])]
        timeline.poll([pullRequest], [detail])
        timeline.config.mutes[pullRequest.id] = Config.MuteEntry(
            ref: pullRequest.ref, scope: .reminders, mutedAt: timeline.now)
        #expect(run(&timeline, pullRequest, detail, for: 2 * hour).isEmpty)
        detail.threads = [
            ReviewThread(
                id: "T0",
                comments: [question, Fixtures.threadComment("TC1", by: "ana", at: timeline.now.addingTimeInterval(1))])
        ]
        timeline.advance(minute)
        let reply = timeline.poll([pullRequest], [detail])
        #expect(reply.notifications.map(\.kind) == [.threadReply])
    }

    @Test("Worked example #26: muting everything still lists and counts it")
    func example26() {
        var timeline = Timeline()
        timeline.poll([])
        timeline.advance(minute)
        var (pullRequest, detail) = requested(timeline: &timeline)
        timeline.config.mutes[pullRequest.id] = Config.MuteEntry(
            ref: pullRequest.ref, scope: .all, mutedAt: timeline.now)
        let first = timeline.poll([pullRequest], [detail])
        #expect(first.notifications.isEmpty)
        timeline.advance(2 * hour)
        detail.requestEvents.append(Fixtures.request("E2", at: timeline.now))
        let again = timeline.poll([pullRequest], [detail])
        #expect(again.notifications.isEmpty)
        let items = Watch.items(
            cache: again.cache.pullRequests, config: timeline.config, state: again.state, now: Fixtures.now)
        #expect(Count.count(items) == 1)
    }

    @Test("Worked example #27: reminders coalesce by repository")
    func example27() {
        var timeline = Timeline()
        let api = (0..<3).map { Fixtures.pullRequest("PR_\($0)", number: 480 + $0, requests: [.user(login: "you")]) }
        let web = Fixtures.pullRequest("PR_W", number: 88, repository: "acme/web", requests: [.user(login: "you")])
        let all = api + [web]
        let details = all.map {
            PullRequestDetail(id: $0.id, requestEvents: [Fixtures.request("E\($0.id)", at: timeline.now)])
        }
        timeline.poll(all, details)
        timeline.advance(hour)
        let output = timeline.poll(all, details)
        let groups = output.notifications.compactMap { notification -> (String?, Int)? in
            if case .reminders(let reminders) = notification.content {
                return (notification.repository, reminders.count)
            }
            return nil
        }
        #expect(groups.count == 2)
        #expect(groups.first { $0.0 == "acme/api" }?.1 == 3)
        #expect(groups.first { $0.0 == "acme/web" }?.1 == 1)
    }

    @Test("Worked example #28: a shorter interval means one reminder now, then the new cadence")
    func example28() {
        var timeline = Timeline()
        timeline.poll([])
        timeline.advance(minute)
        let (pullRequest, detail) = requested(timeline: &timeline)
        timeline.poll([pullRequest], [detail])
        timeline.advance(49 * minute)
        timeline.poll([pullRequest], [detail])
        timeline.config.reminders.intervalMinutes = 15
        #expect(run(&timeline, pullRequest, detail, for: 31 * minute) == [minute, 16 * minute, 31 * minute])
    }

    @Test("Worked example #29: quiet hours follow the Mac's time zone")
    func example29() throws {
        let quiet = Config.QuietHours(enabled: true, start: "22:00", end: "08:00")
        let lisbon = try #require(TimeZone(identifier: "Europe/Lisbon"))
        let saoPaulo = try #require(TimeZone(identifier: "America/Sao_Paulo"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = lisbon
        let lateInLisbon = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 23)))
        #expect(Reminders.inQuietHours(lateInLisbon, quiet, timeZone: lisbon))
        #expect(!Reminders.inQuietHours(lateInLisbon, quiet, timeZone: saoPaulo))
    }

    @Test("Worked example #30: presence is not read; a locked screen changes nothing")
    func example30() {
        var timeline = Timeline()
        timeline.poll([])
        timeline.advance(minute)
        let (pullRequest, detail) = requested(timeline: &timeline)
        timeline.poll([pullRequest], [detail])
        #expect(run(&timeline, pullRequest, detail, for: 2.5 * hour) == [hour, 2 * hour])
    }

    @Test func theDaylightSavingChangeoverKeepsLocalTimes() throws {
        // Lisbon falls back from 02:00 WEST to 01:00 WET on 2026-10-25.
        let lisbon = try #require(TimeZone(identifier: "Europe/Lisbon"))
        let quiet = Config.QuietHours(enabled: true, start: "01:30", end: "02:30")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = lisbon
        let before = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 0, minute: 45)))
        let firstPass = before.addingTimeInterval(55 * 60)
        let secondPass = before.addingTimeInterval(115 * 60)
        let after = before.addingTimeInterval(190 * 60)
        #expect(!Reminders.inQuietHours(before, quiet, timeZone: lisbon))
        #expect(Reminders.inQuietHours(firstPass, quiet, timeZone: lisbon))
        #expect(Reminders.inQuietHours(secondPass, quiet, timeZone: lisbon))
        #expect(!Reminders.inQuietHours(after, quiet, timeZone: lisbon))
    }

    @Test func quietHoursParsingAndDegenerateWindows() {
        #expect(Reminders.minutes("08:30") == 510)
        #expect(Reminders.minutes("24:00") == nil)
        #expect(Reminders.minutes("8") == nil)
        let same = Config.QuietHours(enabled: true, start: "08:00", end: "08:00")
        #expect(!Reminders.inQuietHours(Fixtures.now, same, timeZone: .gmt))
        let daytime = Config.QuietHours(enabled: true, start: "09:00", end: "17:00")
        #expect(Reminders.inQuietHours(Fixtures.now, daytime, timeZone: .gmt))
    }

    @Test func theDefaultConfigNotifiesTheRequestOnceAndNeverReminds() {
        var timeline = Timeline()
        timeline.config = Config()
        timeline.poll([])
        timeline.advance(minute)
        let (pullRequest, detail) = requested(timeline: &timeline)
        let first = timeline.poll([pullRequest], [detail])
        #expect(first.notifications.map(\.kind) == [.reviewRequested])
        #expect(run(&timeline, pullRequest, detail, for: 5 * hour).isEmpty)
    }

    @Test func remindersOffOrHoldingSendNothing() {
        for holding in [false, true] {
            var timeline = Timeline()
            if holding {
                timeline.state.focusHold = FocusHold(since: timeline.now)
            } else {
                timeline.config.reminders.enabled = false
            }
            timeline.poll([])
            timeline.advance(minute)
            let (pullRequest, detail) = requested(timeline: &timeline)
            timeline.poll([pullRequest], [detail])
            #expect(run(&timeline, pullRequest, detail, for: 2 * hour).isEmpty)
        }
    }
}
