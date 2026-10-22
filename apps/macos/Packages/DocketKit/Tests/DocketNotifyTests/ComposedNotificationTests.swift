import DocketCore
import DocketTestSupport
import Foundation
import Testing

@testable import DocketNotify

struct ComposedNotificationTests {
    private let now = Fixtures.now

    private func event(
        _ kind: EventKind, _ id: String, number: Int = 482, repository: String = "acme/api", actor: String = "ana",
        title: String = "Fix login redirect loop", decision: ReviewState? = nil, team: Reviewer? = nil
    ) -> Event {
        var event = Event(
            kind: kind, itemID: id, pullRequestID: "PR_\(number)", repository: repository, number: number, title: title,
            url: Fixtures.url("\(repository)/pull/\(number)#\(id)"), actor: actor, decision: decision, at: now)
        event.team = team
        return event
    }

    private func compose(_ kind: EventKind, _ events: [Event]) -> ComposedNotification {
        ComposedNotification(
            PlannedNotification(repository: events.first?.repository, content: .events(kind, events)), now: now)
    }

    @Test func oneReviewRequestNamesTheRequesterAndTeam() {
        let one = compose(
            .reviewRequested, [event(.reviewRequested, "E1", team: .team(organization: "acme", slug: "backend"))])
        #expect(one.title == "@ana is waiting for your review")
        #expect(one.subtitle == "acme/api #482")
        #expect(one.body == "Fix login redirect loop · via @acme/backend")
        #expect(one.category == .single)
        #expect(one.threadIdentifier == "repo:acme/api")
        #expect(one.url == Fixtures.url("acme/api/pull/482#E1"))
    }

    @Test func groupsCountAndListOneLinePerPullRequest() {
        let three = compose(
            .reviewRequested,
            [
                event(.reviewRequested, "E1"), event(.reviewRequested, "E2", number: 483, title: "Second"),
                event(.reviewRequested, "E3", number: 484, title: "Third"),
            ])
        #expect(three.title == "3 reviews requested")
        #expect(three.subtitle == "acme/api")
        #expect(three.body == "#482 Fix login redirect loop\n#483 Second\n#484 Third")
        #expect(three.category == .group)
        #expect(three.url == nil)
    }

    @Test(arguments: [
        (ReviewState.approved, "@bruno approved"), (.changesRequested, "@bruno requested changes"),
        (.commented, "@bruno commented"),
    ])
    func reviewsSayTheDecision(decision: ReviewState, title: String) {
        let one = compose(
            .reviewSubmitted, [event(.reviewSubmitted, "R1", number: 470, actor: "bruno", decision: decision)])
        #expect(one.title == title)
        #expect(one.subtitle == "acme/api #470")
    }

    @Test func groupedReviewsRepliesAndComments() {
        let reviews = compose(
            .reviewSubmitted,
            [
                event(.reviewSubmitted, "R1", number: 470, actor: "bruno", decision: .approved),
                event(.reviewSubmitted, "R2", number: 471, actor: "carla", decision: .changesRequested),
            ])
        #expect(reviews.title == "2 reviews on your pull requests")
        #expect(reviews.body == "@bruno approved #470\n@carla requested changes #471")
        let replies = compose(
            .threadReply,
            [
                event(.threadReply, "C1", number: 88, actor: "carla"),
                event(.threadReply, "C2", number: 91, actor: "dave"),
            ])
        #expect(replies.title == "2 replies to your comments")
        #expect(replies.body == "@carla on #88\n@dave on #91")
        #expect(
            compose(.threadReply, [event(.threadReply, "C1", actor: "carla")]).title == "@carla replied to your comment"
        )
        #expect(compose(.commentAdded, [event(.commentAdded, "C1", actor: "dave")]).title == "@dave commented")
        #expect(
            compose(.commentAdded, [event(.commentAdded, "C1"), event(.commentAdded, "C2")]).title
                == "2 comments on your pull requests")
    }

    @Test func longGroupsEndWithAndMore() {
        let six = compose(
            .reviewRequested, (0..<6).map { event(.reviewRequested, "E\($0)", number: 480 + $0, title: "T\($0)") })
        #expect(six.body == "#480 T0\n#481 T1\n#482 T2\nand 3 more")
    }

    @Test func longTitlesStopAtAWord() {
        let title = String(repeating: "word ", count: 30)
        let truncated = ComposedNotification.truncated(title)
        #expect(truncated.count <= 80)
        #expect(truncated.hasSuffix("word…"))
    }

    @Test func remindersOneAndMany() {
        let reminder = Reminder(
            pullRequestID: "PR_1", repository: "acme/api", number: 482, title: "Fix login redirect loop",
            url: Fixtures.url("acme/api/pull/482"), requestedAt: now.addingTimeInterval(-7200), requestedBy: "ana",
            at: now)
        let one = ComposedNotification(
            PlannedNotification(repository: "acme/api", content: .reminders([reminder])), now: now)
        #expect(one.title == "Your review is still waiting")
        #expect(one.body == "Fix login redirect loop · requested 2h ago by @ana")
        #expect(one.category == .reminder)
        #expect(one.pullRequestID == "PR_1")
        var second = reminder
        second.pullRequestID = "PR_2"
        second.number = 483
        let many = ComposedNotification(
            PlannedNotification(repository: "acme/api", content: .reminders([reminder, second, reminder])), now: now)
        #expect(many.title == "3 reviews still waiting for you")
        #expect(many.body.hasPrefix("#482 Fix login redirect loop · 2h\n#483"))
    }

    @Test func overflowAndDigest() {
        let overflow = ComposedNotification(
            PlannedNotification(repository: nil, content: .overflow(updates: 7, repositories: 2)), now: now)
        #expect(overflow.title == "7 more updates in 2 repositories")
        #expect(overflow.url == nil)
        let held = [
            HeldEvent(event(.reviewRequested, "E1")), HeldEvent(event(.reviewRequested, "E2", number: 483)),
            HeldEvent(event(.reviewSubmitted, "R1", number: 88, actor: "bruno", decision: .approved)),
        ]
        let digest = ComposedNotification(PlannedNotification(repository: "acme/api", content: .digest(held)), now: now)
        #expect(digest.title == "While you were in Focus")
        #expect(digest.body == "2 reviews requested\n@bruno approved #88")
        #expect(digest.category == .digest)
    }

    @Test func clicksRouteToTheURLThePopoverOrAMute() {
        let single = compose(.commentAdded, [event(.commentAdded, "C1")])
        let info = NotificationClick.userInfo(for: single)
        #expect(
            NotificationClick.route(action: "com.apple.UNNotificationDefaultActionIdentifier", userInfo: info)
                == .open(Fixtures.url("acme/api/pull/482#C1")))
        #expect(
            NotificationClick.route(action: UserNotificationSink.openDocketAction, userInfo: info)
                == .popover(repository: "acme/api"))
        let group = compose(.commentAdded, [event(.commentAdded, "C1"), event(.commentAdded, "C2")])
        #expect(
            NotificationClick.route(action: "default", userInfo: NotificationClick.userInfo(for: group))
                == .popover(repository: "acme/api"))
        let reminder = Reminder(
            pullRequestID: "PR_1", repository: "acme/api", number: 482, title: "t",
            url: Fixtures.url("acme/api/pull/482"),
            requestedAt: now, requestedBy: nil, at: now)
        let composed = ComposedNotification(
            PlannedNotification(repository: "acme/api", content: .reminders([reminder])), now: now)
        #expect(
            NotificationClick.route(
                action: UserNotificationSink.muteRemindersAction, userInfo: NotificationClick.userInfo(for: composed))
                == .muteReminders(pullRequestID: "PR_1", ref: "acme/api#482"))
    }
}

struct LaterKindCopyTests {
    @Test func checksClosedAndMentions() {
        let now = Fixtures.now
        func event(_ kind: EventKind, actor: String? = "bruno", merged: Bool? = nil) -> Event {
            var event = Event(
                kind: kind, itemID: "X", pullRequestID: "PR_1", repository: "acme/api", number: 470, title: "Cache it",
                url: Fixtures.url("acme/api/pull/470"), actor: actor, at: now)
            event.merged = merged
            return event
        }
        func title(_ event: Event) -> String {
            ComposedNotification(
                PlannedNotification(repository: "acme/api", content: .events(event.kind, [event])), now: now
            ).title
        }
        #expect(title(event(.checksFailed, actor: nil)) == "Checks failed")
        #expect(title(event(.closedByOther, merged: true)) == "@bruno merged your pull request")
        #expect(title(event(.closedByOther, merged: false)) == "@bruno closed your pull request")
        #expect(title(event(.mention, actor: "carla")) == "@carla mentioned you")
    }
}
