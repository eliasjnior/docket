import DocketCore
import Foundation
import Testing

@testable import DocketGitHub

@Suite(.serialized)
struct GraphQLClientTests {
    private func client(_ stubs: [StubURLProtocol.Stub], tokens: [String] = ["t1"]) -> (GraphQLClient, ScriptedTokens) {
        StubURLProtocol.reset(stubs)
        let provider = ScriptedTokens(tokens)
        return (
            GraphQLClient(
                tokens: provider, session: GraphQLClient.makeSession(protocolClasses: [StubURLProtocol.self])), provider
        )
    }

    private func ok(_ fixture: String, headers: [String: String] = [:]) -> StubURLProtocol.Stub {
        StubURLProtocol.Stub(status: 200, headers: headers, body: StubURLProtocol.fixture(fixture))
    }

    private func body(_ request: URLRequest) -> [String: Any] {
        (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
    }

    @Test func viewerReadsLoginRateLimitAndServerTime() async throws {
        let (client, _) = client([
            ok("viewer", headers: ["X-OAuth-Scopes": "repo, read:org, gist", "Date": "Wed, 21 Oct 2026 12:00:05 GMT"])
        ])
        let response = try await client.viewer()
        #expect(response.value.login == "you")
        #expect(
            response.meta.rateLimit
                == RateLimit(cost: 1, remaining: 4990, limit: 5000, resetAt: Date(timeIntervalSince1970: 1_792_587_600))
        )
        #expect(response.meta.serverDate == Date(timeIntervalSince1970: 1_792_584_005))
        let request = try #require(StubURLProtocol.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "bearer t1")
    }

    @Test(arguments: [
        ("repo, gist", ["read:org"]), ("read:org", ["repo"]), ("", ["repo", "read:org"]), ("repo, admin:org", []),
    ])
    func missingScopesAreNamed(header: String, missing: [String]) async throws {
        let (client, _) = client([ok("viewer", headers: ["X-OAuth-Scopes": header])])
        if missing.isEmpty {
            _ = try await client.viewer()
        } else {
            await #expect(throws: GitHubError.missingScopes(missing)) { try await client.viewer() }
        }
    }

    @Test func discoveryRunsTheFourSearchesAndPaginatesToOneFifty() async throws {
        let (client, _) = client([ok("search-first"), ok("search-next"), ok("search-next")])
        let since = Date(timeIntervalSince1970: 1_789_992_000)
        let response = try await client.discover(login: "you", since: since)
        #expect(response.value.authored == ["PR_A1", "PR_A2"])
        #expect(response.value.requested == ["PR_R1", "PR_R2", "PR_R2"])
        #expect(response.value.commented == ["PR_A1"])
        #expect(response.value.notShown == ["requested": 157])
        #expect(response.meta.rateLimit?.cost == 3)

        let requests = StubURLProtocol.requests
        #expect(requests.count == 3)
        let first = try #require(body(requests[0])["variables"] as? [String: Any])
        #expect(first["authored"] as? String == "is:pr is:open archived:false author:you")
        #expect(first["requested"] as? String == "is:pr is:open archived:false review-requested:you")
        #expect(
            first["commented"] as? String
                == "is:pr is:open archived:false commenter:you -author:you updated:>=2026-09-21")
        #expect(
            first["reviewed"] as? String
                == "is:pr is:open archived:false reviewed-by:you -author:you updated:>=2026-09-21")
        let second = try #require(body(requests[1])["variables"] as? [String: Any])
        #expect(second["withAuthored"] as? Bool == false)
        #expect(second["withRequested"] as? Bool == true)
        #expect(second["requestedAfter"] as? String == "c1")
    }

    @Test func summariesDecodeAndSortOutNotFoundFromFailed() async throws {
        let (client, _) = client([ok("summary")])
        let batch = try await client.summaries(ids: ["PR_1", "PR_2", "PR_3", "PR_4"]).value
        #expect(batch.notFound == ["PR_2"])
        #expect(batch.failed == ["PR_3"])
        let first = try #require(batch.pullRequests.first)
        #expect(first.ref == "acme/api#482")
        #expect(first.author == Actor(login: "ana"))
        #expect(first.mergeable == .conflicting)
        #expect(first.checks == .failure)
        #expect(first.pendingChecks == nil)
        #expect(first.additions == 120 && first.deletions == 30 && first.changedFiles == 8)
        #expect(first.headOID == "abc123")
        #expect(first.reviewDecision == .reviewRequired)
        #expect(first.reviewRequests == [.user(login: "you"), .team(organization: "acme", slug: "backend")])
        #expect(first.latestReviews == [LatestReview(login: "bruno", state: .approved)])
        #expect(first.labels == [Label(name: "backend", color: "0e8a16")])
        #expect(first.headRefName == "api-12-login-loop")
        #expect(first.baseRefName == "main")
        #expect(first.issueLinks.map(\.absoluteString) == ["https://acme.atlassian.net/browse/API-12"])
        #expect(first.headCommit == CommitStamp(login: "ana", at: Date(timeIntervalSince1970: 1_792_573_200)))
        #expect(first.lastForcePush?.login == "dependabot")
        #expect(first.lastForcePush?.isBot == true)
        let draft = try #require(batch.pullRequests.last)
        #expect(draft.isDraft && draft.isArchived)
        #expect(draft.author?.isBot == true)
        #expect(draft.mergeable == .unknown)
        #expect(draft.checks == nil)
        #expect(draft.additions == nil)
        #expect(draft.labels.isEmpty && draft.issueLinks.isEmpty && draft.headCommit == nil)
    }

    @Test func aPendingRollupSaysWhatRunsAndWhatWaits() async throws {
        let (client, _) = client([ok("summary-pending"), ok("checks-pending")])
        let batch = try await client.summaries(ids: ["PR_9", "PR_10"]).value
        #expect(StubURLProtocol.requests.count == 2)
        #expect(
            (body(StubURLProtocol.requests[1])["variables"] as? [String: Any])?["ids"] as? [String] == [
                "PR_9", "PR_10",
            ])
        let waiting = try #require(batch.pullRequests.first { $0.id == "PR_9" }?.pendingChecks)
        #expect(waiting.running == 0)
        #expect(waiting.waiting.map(\.name) == ["deploy / staging", "e2e"])
        #expect(waiting.waiting.map(\.isApproval) == [true, false])
        #expect(waiting.waiting.last?.detail == "Comment /e2e to run")
        #expect(waiting.waiting.last?.url?.absoluteString == "https://github.com/acme/api/pull/470#issuecomment-1")
        let running = try #require(batch.pullRequests.first { $0.id == "PR_10" }?.pendingChecks)
        #expect(running == PendingChecks(running: 2, waiting: []))
    }

    @Test func pendingChecksThatCannotBeReadLeaveThePollStanding() async throws {
        let (client, _) = client([ok("summary-pending"), StubURLProtocol.Stub(status: 504, body: Data())])
        let batch = try await client.summaries(ids: ["PR_9", "PR_10"]).value
        #expect(batch.pullRequests.count == 2)
        #expect(batch.pullRequests.allSatisfy { $0.checks == .pending && $0.pendingChecks == nil })
    }

    @Test func summariesAreReadInBatchesOfAHundred() async throws {
        let (client, _) = client([ok("summary"), ok("summary")])
        _ = try await client.summaries(ids: (0..<150).map { "PR_\($0)" })
        let sizes = StubURLProtocol.requests.compactMap {
            (body($0)["variables"] as? [String: Any])?["ids"] as? [String]
        }.map(\.count)
        #expect(sizes == [100, 50])
    }

    @Test func detailsDecodeEveryItemAndOnlyWhetherABodyIsEmpty() async throws {
        let (client, _) = client([ok("detail")])
        let detail = try #require(try await client.details(ids: ["PR_1"]).value.first)
        #expect(detail.reviews.map(\.bodyIsEmpty) == [true, false])
        #expect(detail.reviews[1].author?.isBot == true)
        #expect(detail.comments.map(\.id) == ["IC_1"])
        #expect(detail.threads.first?.comments.map(\.reviewID) == ["PRR_0", "PRR_1"])
        #expect(
            detail.requestEvents == [
                ReviewRequestEvent(
                    id: "RRE_1", createdAt: Date(timeIntervalSince1970: 1_792_569_600), actor: Actor(login: "ana"),
                    reviewer: .user(login: "you"))
            ])
    }

    @Test func historyDecodesRequestsAndReviews() async throws {
        let (client, _) = client([ok("history")])
        let histories = try await client.history(query: "is:pr author:you").value
        #expect(histories.count == 1)
        let history = try #require(histories.first)
        #expect(history.mergedAt == Date(timeIntervalSince1970: 1_792_584_000))
        #expect(history.requests.map(\.reviewer) == [.user(login: "ana")])
        #expect(history.reviews.map(\.state) == [.approved])
    }

    @Test func teamsAndRepositories() async throws {
        let (client, _) = client([ok("teams"), ok("repository-found"), ok("repository-missing")])
        #expect(try await client.teams(organization: "acme", login: "you").value == ["backend", "platform"])
        #expect(try await client.repositoryExists("acme/api"))
        #expect(try await !client.repositoryExists("acme/gone"))
        #expect(try await !client.repositoryExists("not-a-repository"))
    }

    @Test func a401ReadsTheTokenOnceAndRetries() async throws {
        let (client, tokens) = client(
            [StubURLProtocol.Stub(status: 401, body: Data()), ok("viewer")], tokens: ["old", "new"])
        #expect(try await client.viewer().value.login == "you")
        #expect(await tokens.refreshes == 1)
        #expect(StubURLProtocol.requests.last?.value(forHTTPHeaderField: "Authorization") == "bearer new")
    }

    @Test func a401WithTheSameTokenIsSignedOut() async throws {
        let (client, _) = client([StubURLProtocol.Stub(status: 401, body: Data())], tokens: ["same"])
        await #expect(throws: GitHubError.unauthorized) { try await client.viewer() }
    }

    @Test func rateLimitsAreTyped() async throws {
        let (client, _) = client([
            StubURLProtocol.Stub(status: 403, headers: ["Retry-After": "60"], body: Data()),
            StubURLProtocol.Stub(
                status: 403, headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1792587600"], body: Data()),
            StubURLProtocol.Stub(status: 502, body: Data()),
        ])
        await #expect(throws: GitHubError.secondaryRateLimit(retryAfter: 60)) { try await client.viewer() }
        await #expect(throws: GitHubError.rateLimited(resetAt: Date(timeIntervalSince1970: 1_792_587_600))) {
            try await client.viewer()
        }
        await #expect(throws: GitHubError.server(status: 502)) { try await client.viewer() }
    }

    @Test func aNetworkFailureIsTyped() async throws {
        let (client, _) = client([])
        await #expect(throws: GitHubError.network) { try await client.viewer() }
    }

    @Test func partialResultsNameTheOrganizationsByLogin() async throws {
        let (client, _) = client([
            ok("summary", headers: ["X-GitHub-SSO": "partial-results; organizations=21955855"]),
            StubURLProtocol.Stub(body: Data(#"{"login":"acme","id":21955855}"#.utf8)),
            ok("summary", headers: ["X-GitHub-SSO": "partial-results; organizations=21955855"]),
        ])
        #expect(try await client.summaries(ids: ["PR_1"]).meta.samlOrganizations == ["acme"])
        #expect(try await client.summaries(ids: ["PR_1"]).meta.samlOrganizations == ["acme"])
        #expect(StubURLProtocol.requests.count == 3)
    }

    @Test func requiredSSONamesTheAuthorizationURL() async throws {
        let (client, _) = client([
            ok(
                "viewer",
                headers: ["X-GitHub-SSO": "required; url=https://github.com/orgs/acme/sso?authorization_request=x"])
        ])
        #expect(
            try await client.viewer().meta.samlURL
                == URL(string: "https://github.com/orgs/acme/sso?authorization_request=x"))
    }

    @Test("Every request goes to api.github.com and none is a mutation (NFR-10, FR-85)")
    func everyRequestIsAReadAgainstGitHub() async throws {
        let (client, _) = client([
            ok("viewer"), ok("search-first"), ok("search-next"), ok("search-next"), ok("summary"), ok("detail"),
            ok("teams"), ok("repository-found"),
        ])
        _ = try await client.viewer()
        _ = try await client.discover(login: "you", since: .distantPast)
        _ = try await client.summaries(ids: ["PR_1"])
        _ = try await client.details(ids: ["PR_1"])
        _ = try await client.teams(organization: "acme", login: "you")
        _ = try await client.repositoryExists("acme/api")
        let requests = StubURLProtocol.requests
        #expect(requests.count == 8)
        for request in requests {
            #expect(request.url?.host == "api.github.com")
            let query = (body(request)["query"] as? String ?? "").lowercased()
            #expect(!query.contains("mutation"))
        }
    }
}
