import DocketCore
import Foundation
import Synchronization

/// A synthetic GitHub, served at the network edge by `GitHubURLProtocol` in GraphQL's own JSON shape, so
/// tests exercise the real client (`docs/03-architecture.md` §7).
public struct GitHubWorld: Sendable {
    public var login = Fixtures.you
    public var scopes = "repo, read:org"
    public var pullRequests: [PullRequest] = []
    public var details: [String: PullRequestDetail] = [:]
    public var discovery = Discovery()
    public var teams: [String: [String]] = [:]
    public var repositories: Set<String> = []
    public var serverDate: Date?
    /// Answer every request with this status instead.
    public var status: Int?
    public var remaining = 4990
    public var limit = 5000

    public init() {}

    private static let world = Mutex(GitHubWorld())
    private static let recorded = Mutex<[String]>([])

    public static func set(_ world: GitHubWorld) {
        self.world.withLock { $0 = world }
        recorded.withLock { $0 = [] }
    }

    public static func update(_ change: (inout GitHubWorld) -> Void) {
        world.withLock { change(&$0) }
    }

    /// The `query` of every GraphQL request served, in order.
    public static var queries: [String] { recorded.withLock { $0 } }

    static func respond(to body: Data) -> Response {
        let request = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let query = request["query"] as? String ?? ""
        let variables = request["variables"] as? [String: Any] ?? [:]
        recorded.withLock { $0.append(query) }
        let world = self.world.withLock { $0 }
        var headers = ["X-OAuth-Scopes": world.scopes, "Content-Type": "application/json"]
        if let date = world.serverDate { headers["Date"] = httpDate(date) }
        if let status = world.status { return Response(status: status, headers: headers, body: Data()) }
        let data: [String: Any]
        if query.contains("query { viewer {") {
            data = ["viewer": ["login": world.login]]
        } else if query.contains("search(") {
            data = world.search(variables)
        } else if query.contains("reviewThreads") {
            let ids = variables["ids"] as? [String] ?? []
            data = ["nodes": ids.map { id in GitHubJSON.optional(world.details[id].map(GitHubJSON.detail)) }]
        } else if query.contains("nodes(ids") {
            let ids = variables["ids"] as? [String] ?? []
            data = [
                "nodes": ids.map { id in
                    GitHubJSON.optional(world.pullRequests.first { $0.id == id }.map(GitHubJSON.summary))
                }
            ]
        } else if query.contains("organization(login") {
            let slugs = world.teams[variables["organization"] as? String ?? ""] ?? []
            data = ["organization": ["teams": ["nodes": slugs.map { ["slug": $0] }]]]
        } else {
            let name = "\(variables["owner"] as? String ?? "")/\(variables["name"] as? String ?? "")"
            data = ["repository": GitHubJSON.optional(world.repositories.contains(name) ? ["id": "R_1"] : nil)]
        }
        var payload = data
        payload["rateLimit"] = [
            "cost": 1, "remaining": world.remaining, "limit": world.limit,
            "resetAt": GitHubJSON.date(Fixtures.now.addingTimeInterval(3600)),
        ]
        let json = (try? JSONSerialization.data(withJSONObject: ["data": payload])) ?? Data()
        return Response(status: 200, headers: headers, body: json)
    }

    struct Response {
        var status: Int
        var headers: [String: String]
        var body: Data
    }

    private func search(_ variables: [String: Any]) -> [String: Any] {
        var data: [String: Any] = [:]
        let lists = [
            "authored": discovery.authored, "requested": discovery.requested, "commented": discovery.commented,
            "reviewed": discovery.reviewed,
        ]
        for (alias, ids) in lists where variables["with\(alias.capitalized)"] as? Bool ?? true {
            data[alias] = [
                "issueCount": ids.count, "pageInfo": ["hasNextPage": false, "endCursor": NSNull()],
                "nodes": ids.map { ["id": $0, "updatedAt": GitHubJSON.date(Fixtures.now)] },
            ]
        }
        return data
    }

    private static func httpDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.string(from: date)
    }
}

/// Serves `GitHubWorld`. Register it with `GraphQLClient.makeSession(protocolClasses:)`.
public final class GitHubURLProtocol: URLProtocol {
    override public static func canInit(with request: URLRequest) -> Bool { true }
    override public static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override public func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 65536)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            stream.close()
        }
        let served = GitHubWorld.respond(to: body)
        guard let url = request.url,
            let response = HTTPURLResponse(
                url: url, statusCode: served.status, httpVersion: "HTTP/1.1", headerFields: served.headers)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: served.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override public func stopLoading() {}
}
