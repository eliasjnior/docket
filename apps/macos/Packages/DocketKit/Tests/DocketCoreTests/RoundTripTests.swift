import DocketCore
import Foundation
import Testing

struct RoundTripTests {
    private let at = Date(timeIntervalSince1970: 1_800_000_000)

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: encoder.encode(value))
    }

    private func pullRequest() throws -> PullRequest {
        PullRequest(
            id: "PR_1", number: 482, title: "Fix login redirect loop",
            url: try #require(URL(string: "https://github.com/acme/api/pull/482")), createdAt: at, updatedAt: at,
            author: Actor(login: "ana"), repository: "acme/api", mergeable: .conflicting,
            reviewDecision: .changesRequested, checks: .pending, headOID: "abc",
            reviewRequests: [.user(login: "you"), .team(organization: "acme", slug: "backend")],
            latestReviews: [LatestReview(login: "bruno", state: .changesRequested)]
        )
    }

    @Test func pullRequestRoundTripsAndNamesItsReference() throws {
        let pullRequest = try pullRequest()
        #expect(try roundTrip(pullRequest) == pullRequest)
        #expect(pullRequest.ref == "acme/api#482")
        #expect(pullRequest.owner == "acme")
    }

    @Test func cacheRoundTrips() throws {
        let cache = SnapshotCache(
            fetchedAt: at, viewerLogin: "you",
            pullRequests: [
                CachedPullRequest(
                    pullRequest: try pullRequest(), role: .reviewRequested,
                    request: RequestInfo(
                        requestedAt: at, requestedBy: "ana", team: .team(organization: "acme", slug: "backend")),
                    commenters: ["dave"])
            ],
            knownRepositories: [KnownRepository(name: "acme/api", lastSeenAt: at)], notShown: ["requested": 3]
        )
        #expect(try roundTrip(cache) == cache)
        #expect(cache.pullRequests.first?.id == "PR_1")
    }

    @Test func detailListsEveryTrackedItem() throws {
        let url = try #require(URL(string: "https://github.com/acme/api/pull/482#c"))
        let detail = PullRequestDetail(
            id: "PR_1",
            reviews: [Review(id: "R1", state: .approved, submittedAt: at, author: Actor(login: "ana"))],
            comments: [Comment(id: "C1", url: url, createdAt: at, author: Actor(login: "dave"))],
            threads: [
                ReviewThread(
                    id: "T1",
                    comments: [ThreadComment(id: "TC1", url: url, createdAt: at, author: nil, reviewID: "R1")])
            ],
            requestEvents: [
                ReviewRequestEvent(id: "E1", createdAt: at, actor: Actor(login: "ana"), reviewer: .user(login: "you"))
            ]
        )
        #expect(detail.itemIDs == ["R1", "C1", "TC1", "E1"])
        #expect(try roundTrip(detail) == detail)
    }

    @Test func plannedNotificationsListWhatTheyDeliver() throws {
        let url = try #require(URL(string: "https://github.com/acme/api/pull/482"))
        let event = Event(
            kind: .commentAdded, itemID: "C1", pullRequestID: "PR_1", repository: "acme/api", number: 482,
            title: "t", url: url, actor: "dave", at: at)
        let reminder = Reminder(
            pullRequestID: "PR_1", repository: "acme/api", number: 482, title: "t", url: url, requestedAt: at,
            requestedBy: "ana", at: at)
        #expect(
            PlannedNotification(repository: "acme/api", content: .events(.commentAdded, [event])).deliveredIDs
                == ["commentAdded:C1"])
        #expect(
            PlannedNotification(repository: "acme/api", content: .reminders([reminder])).deliveredIDs
                == ["reviewReminder:PR_1"])
        #expect(
            PlannedNotification(repository: nil, content: .overflow(updates: 3, repositories: 2)).deliveredIDs
                .isEmpty)
        #expect(
            PlannedNotification(repository: "acme/api", content: .digest([HeldEvent(event)])).deliveredIDs
                == ["commentAdded:C1"])
    }

    @Test func responsesCarryTheirMetadata() {
        let response = GitHubResponse(
            value: Viewer(login: "you"),
            meta: ResponseMeta(rateLimit: RateLimit(cost: 1, remaining: 4999, limit: 5000, resetAt: at)))
        #expect(response.value.login == "you")
        #expect(response.meta.rateLimit?.cost == 1)
        #expect(SummaryBatch(notFound: ["PR_2"]).notFound == ["PR_2"])
    }
}
