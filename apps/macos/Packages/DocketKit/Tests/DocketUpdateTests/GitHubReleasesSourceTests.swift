import Foundation
import Synchronization
import Testing

@testable import DocketUpdate

/// Serves release responses at the URL-loading edge.
final class ReleasesURLProtocol: URLProtocol {
    private static let state = Mutex<(status: Int, requests: [URLRequest])>((200, []))

    static func reset(releasesStatus: Int = 200) { state.withLock { $0 = (releasesStatus, []) } }
    static var requests: [URLRequest] { state.withLock { $0.requests } }

    static let manifest = #"""
        {"version":"0.3.0","build":"12","asset":"Docket-0.3.0.zip","signature":"c2ln","size":3,
        "minimumSystemVersion":"15.0"}
        """#

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let status = Self.state.withLock { state in
            state.requests.append(request)
            return state.status
        }
        let url = request.url?.absoluteString ?? ""
        let (code, body): (Int, Data)
        if url.hasPrefix("https://api.github.com/repos/owner/repo/releases") {
            let fixture = Bundle.module.url(forResource: "releases", withExtension: "json", subdirectory: "Fixtures")
            (code, body) = (status, fixture.flatMap { try? Data(contentsOf: $0) } ?? Data())
        } else if url == "https://api.test/assets/32" {
            (code, body) = (200, Data(Self.manifest.utf8))
        } else if url == "https://api.test/assets/30" {
            (code, body) = (200, Data("zip".utf8))
        } else {
            (code, body) = (404, Data())
        }
        if let target = request.url,
            let response = HTTPURLResponse(url: target, statusCode: code, httpVersion: nil, headerFields: nil)
        {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct GitHubReleasesSourceTests {
    private func source(token: String? = "t0ken", status: Int = 200) -> GitHubReleasesSource {
        ReleasesURLProtocol.reset(releasesStatus: status)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleasesURLProtocol.self]
        return GitHubReleasesSource(
            repository: "owner/repo", session: URLSession(configuration: configuration), token: { token })
    }

    @Test func picksTheNewestPublishedComponentRelease() async throws {
        let source = source()
        let update = try #require(try await source.latest(after: SemanticVersion(major: 0, minor: 2, patch: 0)))
        #expect(update.version.description == "0.3.0")
        #expect(update.manifest.build == "12")
        #expect(update.archiveURL.absoluteString == "https://api.test/assets/30")
        #expect(update.notes.contains("thing"))
        #expect(ReleasesURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer t0ken")
        #expect(ReleasesURLProtocol.requests.last?.value(forHTTPHeaderField: "Accept") == "application/octet-stream")
    }

    @Test func nothingWhenUpToDate() async throws {
        #expect(try await source().latest(after: SemanticVersion(major: 0, minor: 3, patch: 0)) == nil)
    }

    @Test func noAuthorizationWithoutAToken() async throws {
        _ = try await source(token: nil).latest(after: SemanticVersion(major: 1, minor: 0, patch: 0))
        #expect(ReleasesURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func aPrivateRepositoryAnswering404IsUnauthorized() async throws {
        let source = source(status: 404)
        await #expect(throws: UpdateError.unauthorized) {
            try await source.latest(after: SemanticVersion(major: 0, minor: 0, patch: 1))
        }
    }

    @Test func downloadsTheArchive() async throws {
        let source = source()
        let update = try #require(try await source.latest(after: SemanticVersion(major: 0, minor: 1, patch: 0)))
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let file = try await source.downloadArchive(of: update, to: directory)
        #expect(file.lastPathComponent == "Docket-0.3.0.zip")
        #expect(try Data(contentsOf: file) == Data("zip".utf8))
    }

    @Test func versionsParseFromTags() {
        #expect(SemanticVersion("macos-v1.2.3") == SemanticVersion(major: 1, minor: 2, patch: 3))
        #expect(SemanticVersion("1.2") == nil)
        #expect(AppInfo(version: "1.0.0", build: "7").displayVersion == "1.0.0 (7)")
    }
}
