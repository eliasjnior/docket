import DocketActivity
import DocketCore
import DocketTestSupport
import Foundation
import Testing

struct RoleTests {
    private let viewer = ViewerContext(login: "you", teams: ["acme": ["backend"]])
    private let now = Fixtures.now

    private func role(
        _ pullRequest: PullRequest, detail: PullRequestDetail? = nil, hits: DiscoveryHits = DiscoveryHits(),
        previous: Cursor? = nil, viewer: ViewerContext? = nil
    ) -> Role? {
        Roles.role(
            of: Candidate(
                pullRequest: pullRequest, detail: detail ?? PullRequestDetail(id: pullRequest.id), hits: hits,
                previous: previous),
            viewer: viewer ?? self.viewer, now: now)
    }

    @Test func authoredOutranksEverything() {
        let pullRequest = Fixtures.pullRequest(author: "You", requests: [.user(login: "you")])
        #expect(role(pullRequest, hits: DiscoveryHits(requested: true, involved: true)) == .authored)
    }

    @Test func aDirectRequestIsReviewRequested() {
        #expect(role(Fixtures.pullRequest(requests: [.user(login: "YOU")])) == .reviewRequested)
    }

    @Test func aTeamRequestIsReviewRequested() {
        #expect(
            role(Fixtures.pullRequest(requests: [.team(organization: "acme", slug: "backend")])) == .reviewRequested)
        #expect(role(Fixtures.pullRequest(requests: [.team(organization: "acme", slug: "frontend")])) == nil)
    }

    @Test("Worked example #14: a team request you reviewed after is involved")
    func example14() {
        let team = Reviewer.team(organization: "acme", slug: "backend")
        let pullRequest = Fixtures.pullRequest(requests: [team])
        let detail = PullRequestDetail(
            id: pullRequest.id,
            reviews: [Fixtures.review("R1", by: "you", .commented, at: now.addingTimeInterval(-60))],
            requestEvents: [Fixtures.request("E1", to: team, at: now.addingTimeInterval(-3600))]
        )
        #expect(role(pullRequest, detail: detail) == .involved)
        let watched = WatchedPullRequest(pullRequest: pullRequest, role: .involved, status: .waitingForReview)
        #expect(Count.count([watched]) == 0)
    }

    @Test func aTeamRequestAfterYourReviewIsPendingAgain() {
        let team = Reviewer.team(organization: "acme", slug: "backend")
        let pullRequest = Fixtures.pullRequest(requests: [team])
        let detail = PullRequestDetail(
            id: pullRequest.id,
            reviews: [Fixtures.review("R1", by: "you", .commented, at: now.addingTimeInterval(-7200))],
            requestEvents: [Fixtures.request("E1", to: team, at: now.addingTimeInterval(-3600))]
        )
        #expect(role(pullRequest, detail: detail) == .reviewRequested)
    }

    @Test func withoutReadOrgATeamRequestCountsWhenSearchFoundIt() {
        let pullRequest = Fixtures.pullRequest(requests: [.team(organization: "acme", slug: "backend")])
        let unknown = ViewerContext(login: "you", teams: nil)
        #expect(role(pullRequest, hits: DiscoveryHits(requested: true), viewer: unknown) == .reviewRequested)
        #expect(role(pullRequest, viewer: unknown) == nil)
    }

    @Test func involvedComesFromSearchOrFromTheLastThirtyDays() {
        let pullRequest = Fixtures.pullRequest(updatedAt: now.addingTimeInterval(-Fixtures.days(10)))
        let previous = Cursor(ref: pullRequest.ref, role: .involved, updatedAt: now, enteredAt: now)
        #expect(role(pullRequest, hits: DiscoveryHits(involved: true)) == .involved)
        #expect(role(pullRequest, previous: previous) == .involved)
        let old = Fixtures.pullRequest(updatedAt: now.addingTimeInterval(-Fixtures.days(31)))
        #expect(role(old, previous: previous) == nil)
    }

    @Test(arguments: [PullRequestState.closed, .merged])
    func closedOrMergedHasNoRole(state: PullRequestState) {
        #expect(role(Fixtures.pullRequest(author: "you", state: state)) == nil)
    }

    @Test func archivedRepositoriesAreNeverWatched() {
        #expect(role(Fixtures.pullRequest(author: "you", isArchived: true)) == nil)
    }

    @Test func theLatestRequestToYouGivesTheWaitedTime() {
        let team = Reviewer.team(organization: "acme", slug: "backend")
        let pullRequest = Fixtures.pullRequest(requests: [team, .user(login: "you")])
        let detail = PullRequestDetail(
            id: pullRequest.id,
            requestEvents: [
                Fixtures.request("E1", at: now.addingTimeInterval(-7200)),
                Fixtures.request("E2", to: team, by: "bruno", at: now.addingTimeInterval(-3600)),
                Fixtures.request("E3", to: .user(login: "carla"), at: now.addingTimeInterval(-60)),
            ]
        )
        let info = Requests.latest(on: pullRequest, detail: detail, viewer: viewer)
        #expect(info?.requestedAt == now.addingTimeInterval(-3600))
        #expect(info?.requestedBy == "bruno")
        #expect(info?.team == team)
    }

    @Test func withoutAVisibleEventTheWaitedTimeRunsFromCreation() {
        let pullRequest = Fixtures.pullRequest(requests: [.user(login: "you")])
        let info = Requests.latest(on: pullRequest, detail: nil, viewer: viewer)
        #expect(info?.requestedAt == pullRequest.createdAt)
        #expect(info?.team == nil)
        let viaTeam = Fixtures.pullRequest(requests: [.team(organization: "acme", slug: "backend")])
        let unknown = Requests.latest(on: viaTeam, detail: nil, viewer: ViewerContext(login: "you", teams: nil))
        #expect(unknown?.throughUnknownTeam == true)
    }
}
