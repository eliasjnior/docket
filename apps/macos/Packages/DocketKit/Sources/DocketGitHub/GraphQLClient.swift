import DocketCore
import Foundation
import os

/// `GitHubSource` over GitHub's GraphQL API. Read-only: no document it sends is a mutation (FR-85).
public actor GraphQLClient: GitHubSource {
    public static let host = "api.github.com"
    public static let requiredScopes = ["repo", "read:org"]

    private let tokens: TokenProvider
    private let session: URLSession
    private let endpoint: URL
    private let restBase: URL
    private var organizationLogins: [String: String] = [:]
    private let log = Logger(subsystem: "com.eliasjnior.docket", category: "github")

    public init(tokens: TokenProvider, session: URLSession = GraphQLClient.makeSession()) {
        self.tokens = tokens
        self.session = session
        endpoint = URL(string: "https://\(Self.host)/graphql") ?? URL(fileURLWithPath: "/")
        restBase = URL(string: "https://\(Self.host)") ?? URL(fileURLWithPath: "/")
    }

    public static func makeSession(protocolClasses: [AnyClass] = []) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.httpAdditionalHeaders = ["User-Agent": "Docket"]
        if !protocolClasses.isEmpty { configuration.protocolClasses = protocolClasses }
        return URLSession(configuration: configuration)
    }

    // MARK: - GitHubSource

    public func viewer() async throws -> GitHubResponse<Viewer> {
        let (envelope, meta) = try await send(Queries.viewer, [:], as: ViewerData.self)
        if let scopes = meta.scopes {
            let missing = Self.missingScopes(in: scopes)
            if !missing.isEmpty { throw GitHubError.missingScopes(missing) }
        }
        guard let data = envelope.data else { throw GitHubError.invalidResponse("viewer") }
        return GitHubResponse(value: Viewer(login: data.viewer.login), meta: meta.with(data.rateLimit))
    }

    public func discover(login: String, since: Date) async throws -> GitHubResponse<Discovery> {
        let day = Self.dayFormatter.string(from: since)
        let base = "is:pr is:open archived:false"
        let queries = [
            "authored": "\(base) author:\(login)",
            "requested": "\(base) review-requested:\(login)",
            "commented": "\(base) commenter:\(login) -author:\(login) updated:>=\(day)",
            "reviewed": "\(base) reviewed-by:\(login) -author:\(login) updated:>=\(day)",
        ]
        var ids: [String: [String]] = [:]
        var totals: [String: Int] = [:]
        // Aliases still to read, with the cursor of their next page; `nil` before the first page.
        var pending: [String: String] = [:]
        var active = Set(Self.aliases)
        var meta = ResponseMeta()
        for _ in 0..<3 where !active.isEmpty {
            var variables: [String: GraphQLValue] = [:]
            for alias in Self.aliases {
                variables[alias] = .string(queries[alias] ?? "")
                variables["with\(alias.capitalized)"] = .bool(active.contains(alias))
                variables["\(alias)After"] = pending[alias].map(GraphQLValue.string) ?? .null
            }
            let (envelope, pageMeta) = try await send(Queries.search, variables, as: SearchData.self)
            meta = meta.merged(pageMeta.with(envelope.data?.rateLimit))
            guard let data = envelope.data else { throw GitHubError.invalidResponse("search") }
            let pages: [String: SearchPage] = [
                "authored": data.authored, "requested": data.requested, "commented": data.commented,
                "reviewed": data.reviewed,
            ].compactMapValues { $0 }
            for alias in active {
                guard let page = pages[alias] else {
                    active.remove(alias)
                    continue
                }
                ids[alias, default: []].append(contentsOf: (page.nodes ?? []).compactMap { $0?.id })
                totals[alias] = page.issueCount
                if page.pageInfo.hasNextPage, let next = page.pageInfo.endCursor {
                    pending[alias] = next
                } else {
                    active.remove(alias)
                }
            }
        }
        var notShown: [String: Int] = [:]
        for alias in Self.aliases {
            let missing = (totals[alias] ?? 0) - (ids[alias]?.count ?? 0)
            if missing > 0 { notShown[alias] = missing }
        }
        let discovery = Discovery(
            authored: ids["authored"] ?? [], requested: ids["requested"] ?? [],
            commented: ids["commented"] ?? [], reviewed: ids["reviewed"] ?? [], notShown: notShown)
        return GitHubResponse(value: discovery, meta: meta)
    }

    public func summaries(ids: [String]) async throws -> GitHubResponse<SummaryBatch> {
        var batch = SummaryBatch()
        var meta = ResponseMeta()
        for chunk in ids.chunked(into: 100) {
            let (envelope, chunkMeta) = try await send(
                Queries.summary, ["ids": .strings(chunk)], as: NodesData<PullRequestDTO>.self)
            meta = meta.merged(chunkMeta.with(envelope.data?.rateLimit))
            let nodes = envelope.data?.nodes ?? []
            let errors = Dictionary(
                (envelope.errors ?? []).compactMap { error in error.nodeIndex.map { ($0, error.type ?? "") } },
                uniquingKeysWith: { first, _ in first })
            for (index, id) in chunk.enumerated() {
                if let pullRequest = (index < nodes.count ? nodes[index] : nil)?.value {
                    batch.pullRequests.append(pullRequest)
                } else if let type = errors[index], type != "NOT_FOUND" {
                    batch.failed.append(id)
                } else {
                    batch.notFound.append(id)
                }
            }
        }
        return GitHubResponse(value: batch, meta: meta)
    }

    public func details(ids: [String]) async throws -> GitHubResponse<[PullRequestDetail]> {
        var details: [PullRequestDetail] = []
        var meta = ResponseMeta()
        for chunk in ids.chunked(into: 10) {
            let (envelope, chunkMeta) = try await send(
                Queries.detail, ["ids": .strings(chunk)], as: NodesData<DetailDTO>.self)
            meta = meta.merged(chunkMeta.with(envelope.data?.rateLimit))
            details.append(contentsOf: (envelope.data?.nodes ?? []).compactMap { $0?.value })
        }
        return GitHubResponse(value: details, meta: meta)
    }

    public func teams(organization: String, login: String) async throws -> GitHubResponse<[String]> {
        let (envelope, meta) = try await send(
            Queries.teams, ["organization": .string(organization), "login": .string(login)], as: TeamsData.self)
        let slugs = envelope.data?.organization?.teams.values.map(\.slug) ?? []
        return GitHubResponse(value: slugs, meta: meta.with(envelope.data?.rateLimit))
    }

    public func repositoryExists(_ nameWithOwner: String) async throws -> Bool {
        let parts = nameWithOwner.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        let (envelope, _) = try await send(
            Queries.repository, ["owner": .string(parts[0]), "name": .string(parts[1])], as: RepositoryData.self)
        return envelope.data?.repository != nil
    }

    // MARK: - Transport

    private static let aliases = ["authored", "requested", "commented", "reviewed"]

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func missingScopes(in scopes: [String]) -> [String] {
        let granted = Set(scopes)
        var missing: [String] = []
        if !granted.contains("repo") { missing.append("repo") }
        if granted.isDisjoint(with: ["read:org", "write:org", "admin:org"]) { missing.append("read:org") }
        return missing
    }

    func send<Payload: Decodable>(
        _ query: String, _ variables: [String: GraphQLValue], as type: Payload.Type
    ) async throws -> (Envelope<Payload>, ResponseMeta) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GraphQLRequest(query: query, variables: variables))

        var token = try await tokens.token()
        var (data, response) = try await perform(request, token: token)
        if response.statusCode == 401 {
            let refreshed = try await tokens.refresh()
            guard refreshed != token else { throw GitHubError.unauthorized }
            token = refreshed
            (data, response) = try await perform(request, token: token)
            if response.statusCode == 401 { throw GitHubError.unauthorized }
        }
        try Self.check(response)
        var meta = ResponseMeta.parse(response)
        if !meta.samlOrganizations.isEmpty {
            meta.samlOrganizations = await resolveOrganizations(meta.samlOrganizations, token: token)
        }
        do {
            let envelope = try Self.decoder.decode(Envelope<Payload>.self, from: data)
            if envelope.data == nil, let message = envelope.errors?.first?.message {
                throw GitHubError.invalidResponse(message)
            }
            return (envelope, meta)
        } catch let error as GitHubError {
            throw error
        } catch {
            log.error("Undecodable response: \(String(describing: error), privacy: .public)")
            throw GitHubError.invalidResponse(String(describing: error))
        }
    }

    private func perform(_ request: URLRequest, token: String) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GitHubError.network
        }
        guard let http = response as? HTTPURLResponse else { throw GitHubError.invalidResponse("not HTTP") }
        return (data, http)
    }

    private static func check(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 403, 429:
            if let retry = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) {
                throw GitHubError.secondaryRateLimit(retryAfter: retry)
            }
            if response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
                let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(TimeInterval.init)
                throw GitHubError.rateLimited(resetAt: reset.map(Date.init(timeIntervalSince1970:)))
            }
            throw GitHubError.server(status: response.statusCode)
        default:
            throw GitHubError.server(status: response.statusCode)
        }
    }

    /// `X-GitHub-SSO: partial-results` names organizations by ID; one `GET /organizations/{id}` each, once.
    private func resolveOrganizations(_ ids: [String], token: String) async -> [String] {
        var logins: [String] = []
        for id in ids {
            if let known = organizationLogins[id] {
                logins.append(known)
                continue
            }
            var request = URLRequest(url: restBase.appending(path: "organizations/\(id)"))
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await perform(request, token: token), response.statusCode == 200,
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let login = object["login"] as? String
            else { continue }
            organizationLogins[id] = login
            logins.append(login)
        }
        return logins
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
