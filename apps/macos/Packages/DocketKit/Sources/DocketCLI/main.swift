import DocketActivity
import DocketCore
import DocketGitHub
import Foundation

/// `docket-cli`: a live check against your own account (`docs/06-engineering-practices.md` §12). It never
/// writes `~/Library/Application Support/Docket/`; its own cursors live in `~/Library/Caches`.
@main
struct DocketCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let tokens = GhTokenProvider()
        let client = GraphQLClient(tokens: tokens)
        do {
            switch arguments.first {
            case "whoami": try await whoami(client)
            case "poll": try await poll(client, fresh: arguments.contains("--fresh"))
            case "stats": try await StatsCommand.run(client, arguments: Array(arguments.dropFirst()))
            default:
                print("usage: docket-cli <whoami | poll [--fresh] | stats [--days N]>")
                exit(64)
            }
        } catch {
            FileHandle.standardError.write(Data("error: \(describe(error))\n".utf8))
            exit(1)
        }
    }

    static func whoami(_ client: GraphQLClient) async throws {
        let viewer = try await client.viewer()
        print("token: present (never printed)")
        print("login: \(viewer.value.login)")
        print("scopes: \(viewer.meta.scopes?.joined(separator: ", ") ?? "unknown")")
        print("rateLimit: \(describe(viewer.meta.rateLimit))")
    }

    static func poll(_ client: GraphQLClient, fresh: Bool) async throws {
        let store = CLIState()
        let viewerResponse = try await client.viewer()
        let login = viewerResponse.value.login
        var state = fresh ? PersistedState(viewerLogin: login) : store.load(login: login)
        let now = Date()
        let discovery = try await client.discover(login: login, since: now.addingTimeInterval(-30 * 86400))
        let ids = PollEngine.summaryIDs(discovery: discovery.value, state: state)
        let summaries = ids.isEmpty ? GitHubResponse(value: SummaryBatch()) : try await client.summaries(ids: ids)
        var costs = [("discovery", discovery.meta), ("summary", summaries.meta)]
        let teams = try await refreshTeams(
            client, summaries.value.pullRequests, login: login, state: &state, costs: &costs)
        let viewer = ViewerContext(login: login, teams: teams)
        let detailIDs = PollEngine.detailIDs(
            summaries: summaries.value.pullRequests, discovery: discovery.value, state: state, viewer: viewer, now: now)
        let details = detailIDs.isEmpty ? GitHubResponse(value: []) : try await client.details(ids: detailIDs)
        costs.append(("detail ×\(detailIDs.count)", details.meta))

        let output = PollEngine.run(
            PollInput(
                viewer: viewer, now: now, state: state, previousCache: store.loadCache(login: login),
                discovery: discovery.value, summaries: summaries.value,
                details: Dictionary(details.value.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })))
        report(output, costs: costs, viewerCost: viewerResponse.meta.rateLimit?.cost ?? 0)
        store.save(output.state, cache: output.cache)
    }

    static func refreshTeams(
        _ client: GraphQLClient, _ pullRequests: [PullRequest], login: String, state: inout PersistedState,
        costs: inout [(String, ResponseMeta)]
    ) async throws -> [String: Set<String>] {
        let now = Date()
        var teams: [String: Set<String>] = [:]
        let organizations = Set(
            pullRequests.flatMap { pullRequest in
                pullRequest.reviewRequests.compactMap { reviewer -> String? in
                    if case .team(let organization, _) = reviewer { return organization.lowercased() }
                    return nil
                }
            })
        for organization in organizations.sorted() {
            if let cached = state.teams[organization], now.timeIntervalSince(cached.fetchedAt) < 3600 {
                teams[organization] = Set(cached.slugs.map { $0.lowercased() })
                continue
            }
            let response = try await client.teams(organization: organization, login: login)
            costs.append(("teams \(organization)", response.meta))
            teams[organization] = Set(response.value.map { $0.lowercased() })
            state.teams[organization] = TeamCache(slugs: response.value, fetchedAt: now)
        }
        return teams
    }

    static func report(_ output: PollOutput, costs: [(String, ResponseMeta)], viewerCost: Int) {
        let items = Watch.items(cache: output.cache.pullRequests, config: Config(), state: output.state, now: Date())
        for role in Role.allCases {
            let rows = items.filter { $0.role == role }
            print("\n\(role.rawValue) (\(rows.count))")
            for item in rows.sorted(by: { $0.pullRequest.ref < $1.pullRequest.ref }) {
                let draft = item.pullRequest.isDraft ? " draft" : ""
                print("  \(item.pullRequest.ref)  \(item.status.rawValue)\(draft)  \(item.pullRequest.title)")
            }
        }
        print("\nneeds you: \(Count.count(items))")
        print("\nevents (\(output.events.count))")
        for event in output.events {
            print("  \(event.kind.rawValue)  \(event.repository)#\(event.number)  by \(event.actor ?? "?")")
        }
        print("\nnotifications (\(output.notifications.count))")
        print("\ncost")
        print("  viewer, once per launch: \(viewerCost)")
        var total = 0
        for (name, meta) in costs {
            let cost = meta.rateLimit?.cost ?? 0
            total += cost
            print("  \(name): \(cost)")
        }
        let remaining = costs.compactMap(\.1.rateLimit).last?.remaining ?? 0
        print("  poll total: \(total)  remaining: \(remaining)")
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func describe(_ rateLimit: RateLimit?) -> String {
        guard let rateLimit else { return "unknown" }
        return "\(rateLimit.remaining) of \(rateLimit.limit) remaining"
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case TokenError.ghNotFound: "GitHub CLI not found: brew install gh"
        case TokenError.signedOut, GitHubError.unauthorized: "GitHub CLI not signed in: gh auth login"
        case GitHubError.missingScopes(let scopes):
            "token missing \(scopes.joined(separator: ", ")): "
                + "gh auth refresh -h github.com -s \(scopes.joined(separator: ","))"
        default: String(describing: error)
        }
    }
}

/// The CLI's own cursors, so a second run diffs against the first.
struct CLIState {
    let directory = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Caches/com.eliasjnior.docket-cli", directoryHint: .isDirectory)

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func load(login: String) -> PersistedState {
        guard let data = try? Data(contentsOf: directory.appending(path: "state.json")),
            let state = try? decoder.decode(PersistedState.self, from: data), state.viewerLogin == login
        else { return PersistedState(viewerLogin: login) }
        return state
    }

    func loadCache(login: String) -> SnapshotCache? {
        guard let data = try? Data(contentsOf: directory.appending(path: "snapshot.json")),
            let cache = try? decoder.decode(SnapshotCache.self, from: data), cache.viewerLogin == login
        else { return nil }
        return cache
    }

    func save(_ state: PersistedState, cache: SnapshotCache) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? encoder.encode(state).write(to: directory.appending(path: "state.json"), options: .atomic)
        try? encoder.encode(cache).write(to: directory.appending(path: "snapshot.json"), options: .atomic)
    }
}

enum StatsCommand {
    static func run(_ client: GraphQLClient, arguments: [String]) async throws {
        let days =
            arguments.firstIndex(of: "--days").flatMap {
                arguments.indices.contains($0 + 1) ? Int(arguments[$0 + 1]) : nil
            } ?? 30
        let login = try await client.viewer().value.login
        let now = Date()
        let since = DocketCLI.day(now.addingTimeInterval(-Double(days) * 86400))
        let reviewed = try await client.history(query: "is:pr reviewed-by:\(login) -author:\(login) updated:>=\(since)")
        let waiting = try await client.history(query: "is:pr is:open review-requested:\(login)")
        let authored = try await client.history(query: "is:pr is:merged author:\(login) merged:>=\(since)")
        var seen = Set<String>()
        let candidates = (reviewed.value + waiting.value).filter { seen.insert($0.id).inserted }
        let report = Stats.report(
            reviewed: candidates, authored: authored.value, viewer: ViewerContext(login: login, teams: nil), now: now,
            calendar: Calendar(identifier: .gregorian))
        print("last \(days) days, for \(login)")
        let median = report.medianTimeToFirstReview.map { RowFormat.duration($0) } ?? "n/a"
        print(
            "  median time from a review request to your first review: \(median) (\(report.answeredRequests) requests)")
        print("  review requests that waited more than 2 working days: \(report.requestsOlderThanTwoWorkingDays)")
        print(
            "  your pull requests approved but not merged for more than 4 hours: "
                + "\(report.approvedButUnmergedOverFourHours) of \(report.mergedPullRequests) merged")
        let cost = [reviewed.meta, waiting.meta, authored.meta].compactMap(\.rateLimit).map(\.cost).reduce(0, +)
        print("  cost: \(cost) points")
    }
}

enum RowFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? "\(Int(seconds)) s"
    }
}
