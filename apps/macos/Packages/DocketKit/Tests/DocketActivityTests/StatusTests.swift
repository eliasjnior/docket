import DocketActivity
import DocketCore
import DocketTestSupport
import Foundation
import Testing

struct StatusTests {
    @Test("Worked example #11: UNKNOWN keeps the last known conflict")
    func example11() {
        let pullRequest = Fixtures.pullRequest(mergeable: .unknown, requests: [.user(login: "ana")])
        #expect(StatusRules.status(of: pullRequest, lastMergeable: .conflicting) == .conflict)
        #expect(StatusRules.status(of: pullRequest, lastMergeable: nil) == .waitingForReview)
    }

    @Test("Worked example #12: approved with running checks is checksRunning, not counted")
    func example12() {
        let pullRequest = Fixtures.pullRequest(author: "you", decision: .approved, checks: .pending)
        let status = StatusRules.status(of: pullRequest, lastMergeable: nil)
        #expect(status == .checksRunning)
        #expect(Count.count([WatchedPullRequest(pullRequest: pullRequest, role: .authored, status: status)]) == 0)
    }

    @Test("Worked example #13: no decision, one approval, green checks is readyToMerge, counted")
    func example13() {
        let pullRequest = Fixtures.pullRequest(
            author: "you", checks: .success, latestReviews: [LatestReview(login: "ana", state: .approved)])
        let status = StatusRules.status(of: pullRequest, lastMergeable: nil)
        #expect(status == .readyToMerge)
        #expect(Count.count([WatchedPullRequest(pullRequest: pullRequest, role: .authored, status: status)]) == 1)
    }

    @Test("Worked example #17: a draft keeps its status and never counts")
    func example17() {
        let pullRequest = Fixtures.pullRequest(author: "you", isDraft: true, checks: .failure)
        let status = StatusRules.status(of: pullRequest, lastMergeable: nil)
        #expect(status == .checksFailing)
        #expect(Count.count([WatchedPullRequest(pullRequest: pullRequest, role: .authored, status: status)]) == 0)
    }

    private static func gate(_ url: String?) -> WaitingCheck {
        WaitingCheck(name: "e2e", detail: "Comment /e2e to run", url: url.flatMap(URL.init(string:)))
    }

    @Test("Worked example #47: a gate that links to the pull request, with nothing running, is checksWaiting")
    func example47() {
        var pullRequest = Fixtures.pullRequest(author: "you", checks: .pending)
        let gate = Self.gate("https://github.com/acme/api/pull/482#issuecomment-1")
        let ci = Self.gate("https://ci.acme.dev/job/12")
        pullRequest.pendingChecks = PendingChecks(running: 0, waiting: [gate, ci])
        let status = StatusRules.status(of: pullRequest, lastMergeable: nil)
        #expect(status == .checksWaiting)
        #expect(StatusRules.waitingChecks(pullRequest) == [gate])
        let item = WatchedPullRequest(pullRequest: pullRequest, role: .authored, status: status)
        #expect(MineKind.of(item) == .blocked)
        #expect(Count.count([item]) == 1)
    }

    @Test("Worked example #48: the same gate while a check run runs is checksRunning")
    func example48() {
        var pullRequest = Fixtures.pullRequest(author: "you", checks: .pending)
        pullRequest.pendingChecks = PendingChecks(
            running: 2, waiting: [Self.gate("https://github.com/acme/api/pull/482#issuecomment-1")])
        #expect(StatusRules.status(of: pullRequest, lastMergeable: nil) == .checksRunning)
    }

    @Test("Worked example #49: an external CI's status is running however long it takes; an approval waits")
    func example49() {
        var pullRequest = Fixtures.pullRequest(author: "you", checks: .pending)
        for url in [
            "https://ci.acme.dev/job/12", "https://github.com/acme/api/actions/runs/7",
            "https://github.com/acme/api/pull/4820", nil,
        ] {
            pullRequest.pendingChecks = PendingChecks(running: 0, waiting: [Self.gate(url)])
            #expect(StatusRules.status(of: pullRequest, lastMergeable: nil) == .checksRunning)
        }
        pullRequest.pendingChecks = PendingChecks(
            running: 0, waiting: [WaitingCheck(name: "deploy / staging", isApproval: true)])
        #expect(StatusRules.status(of: pullRequest, lastMergeable: nil) == .checksWaiting)
    }

    private static let precedenceCases: [(PullRequest, Status)] = {
        let approvedAndChanges = [
            LatestReview(login: "a", state: .approved), LatestReview(login: "b", state: .changesRequested),
        ]
        let changes = [LatestReview(login: "a", state: .changesRequested)]
        var cases: [(PullRequest, Status)] = []
        cases.append((Fixtures.pullRequest(mergeable: .conflicting, checks: .failure), .conflict))
        cases.append((Fixtures.pullRequest(decision: .changesRequested, checks: .error), .checksFailing))
        cases.append((Fixtures.pullRequest(decision: .changesRequested, checks: .pending), .changesRequested))
        cases.append((Fixtures.pullRequest(latestReviews: changes), .changesRequested))
        cases.append((Fixtures.pullRequest(checks: .expected), .checksRunning))
        cases.append((Fixtures.pullRequest(decision: .approved), .readyToMerge))
        cases.append((Fixtures.pullRequest(latestReviews: approvedAndChanges), .changesRequested))
        cases.append(
            (Fixtures.pullRequest(decision: .reviewRequired, requests: [.user(login: "ana")]), .waitingForReview))
        cases.append((Fixtures.pullRequest(decision: .reviewRequired), .noReviewers))
        return cases
    }()

    @Test(arguments: precedenceCases)
    func precedence(pullRequest: PullRequest, expected: Status) {
        #expect(StatusRules.status(of: pullRequest, lastMergeable: nil) == expected)
    }

    private static let ageCases: [(TimeInterval, String)] = [
        (0, "now"), (59, "now"), (60, "1m"), (3599, "59m"), (3600, "1h"), (86399, "23h"),
        (86400, "1d"), (1_206_000, "13d"), (1_209_600, "2w"), (-5, "now"),
    ]

    @Test(arguments: ageCases)
    func ages(elapsed: TimeInterval, expected: String) {
        #expect(Age.short(elapsed) == expected)
    }

    private static let styleCases: [(TimeInterval, Age.Style)] = [
        (259_200, .normal), (259_201, .ageing), (604_800, .ageing), (604_801, .stale),
    ]

    @Test(arguments: styleCases)
    func ageStyles(elapsed: TimeInterval, expected: Age.Style) {
        #expect(Age.style(elapsed) == expected)
    }
}
