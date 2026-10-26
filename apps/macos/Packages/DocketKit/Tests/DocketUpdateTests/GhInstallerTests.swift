import CryptoKit
import Foundation
import Synchronization
import Testing

@testable import DocketUpdate

/// Serves a synthetic `cli/cli` release at the URL-loading edge.
final class GhReleaseURLProtocol: URLProtocol {
    struct Served {
        var bodies: [String: Data] = [:]
        var requests: [URLRequest] = []
    }

    private static let state = Mutex(Served())

    static func serve(_ bodies: [String: Data]) { state.withLock { $0 = Served(bodies: bodies) } }
    static var requests: [URLRequest] { state.withLock { $0.requests } }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.state.withLock { state in
            state.requests.append(request)
            return state.bodies[request.url?.absoluteString ?? ""]
        }
        if let target = request.url,
            let response = HTTPURLResponse(
                url: target, statusCode: body == nil ? 404 : 200, httpVersion: nil, headerFields: nil)
        {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: body ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The signature checks the installer asked for.
final class SignatureChecks: Sendable {
    private let checked = Mutex<[String]>([])
    var paths: [String] { checked.withLock { $0 } }
    func record(_ url: URL) { checked.withLock { $0.append(url.lastPathComponent) } }
}

@Suite(.serialized)
struct GhInstallerTests {
    private let latest = "https://api.github.com/repos/cli/cli/releases/latest"
    private let root = FileManager.default.temporaryDirectory.appending(path: "GhInstallerTests-\(UUID().uuidString)")

    private var destination: URL { root.appending(path: "Support/bin/gh") }

    /// A `gh_9.9.9_macOS_<arch>.zip` laid out like the real one, its executable a tiny script.
    private func archive(architecture: String = "arm64") throws -> Data {
        let folder = root.appending(path: "build/gh_9.9.9_macOS_\(architecture)")
        try FileManager.default.createDirectory(at: folder.appending(path: "bin"), withIntermediateDirectories: true)
        try Data("#!/bin/sh\necho gh version 9.9.9\n".utf8).write(to: folder.appending(path: "bin/gh"))
        let zip = root.appending(path: "build/gh.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", folder.path, zip.path]
        try process.run()
        process.waitUntilExit()
        return try Data(contentsOf: zip)
    }

    private func release(_ names: [String]) -> Data {
        let assets = names.enumerated().map { index, name in
            #"{"name":"\#(name)","url":"https://api.test/assets/\#(index)"}"#
        }
        let head = #""tag_name":"v9.9.9","draft":false,"prerelease":false,"published_at":"2026-10-23T17:14:00Z""#
        let json = "{" + head + #","assets":[\#(assets.joined(separator: ","))]}"#
        return Data(json.utf8)
    }

    private func serve(zip: Data, sum: String? = nil, architecture: String = "arm64") {
        let name = "gh_9.9.9_macOS_\(architecture).zip"
        let digest = sum ?? SHA256.hash(data: zip).map { String(format: "%02x", $0) }.joined()
        GhReleaseURLProtocol.serve([
            latest: release(["gh_9.9.9_checksums.txt", name, "gh_9.9.9_linux_amd64.tar.gz"]),
            "https://api.test/assets/0": Data("0000  gh_9.9.9_linux_amd64.tar.gz\n\(digest)  \(name)\n".utf8),
            "https://api.test/assets/1": zip,
        ])
    }

    private func installer(_ checks: SignatureChecks = SignatureChecks(), rejects: Bool = false) -> GhInstaller {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GhReleaseURLProtocol.self]
        return GhInstaller(
            destination: destination, session: URLSession(configuration: configuration), architecture: "arm64",
            workDirectory: root.appending(path: "work"),
            checkSignature: { url in
                checks.record(url)
                if rejects { throw GhInstallError.badSignature }
            })
    }

    @Test func installsTheVerifiedExecutableForThisArchitecture() async throws {
        serve(zip: try archive())
        let checks = SignatureChecks()
        let installed = try await installer(checks).install()
        #expect(installed == destination)
        #expect(FileManager.default.isExecutableFile(atPath: destination.path))
        #expect((String(bytes: try Data(contentsOf: destination), encoding: .utf8) ?? "").contains("9.9.9"))
        #expect(checks.paths == ["gh"])
        #expect(GhReleaseURLProtocol.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        #expect(GhReleaseURLProtocol.requests.last?.value(forHTTPHeaderField: "Accept") == "application/octet-stream")
    }

    @Test func replacesAnEarlierCopy() async throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: destination)
        serve(zip: try archive())
        _ = try await installer().install()
        #expect((String(bytes: try Data(contentsOf: destination), encoding: .utf8) ?? "").contains("9.9.9"))
    }

    @Test func aChecksumMismatchInstallsNothing() async throws {
        serve(zip: try archive(), sum: String(repeating: "a", count: 64))
        await #expect(throws: GhInstallError.checksumMismatch) { try await installer().install() }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func anExecutableGitHubDidNotSignInstallsNothing() async throws {
        serve(zip: try archive())
        await #expect(throws: GhInstallError.badSignature) { try await installer(rejects: true).install() }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func aReleaseWithoutThisArchitectureIsMissingAnAsset() async throws {
        serve(zip: try archive(architecture: "amd64"), architecture: "amd64")
        await #expect(throws: GhInstallError.missingAsset("gh_9.9.9_macOS_arm64.zip")) {
            try await installer().install()
        }
    }

    @Test func gitHubUnreachableIsUnavailable() async throws {
        GhReleaseURLProtocol.serve([:])
        await #expect(throws: GhInstallError.unavailable(404)) { try await installer().install() }
    }

    @Test func readsTheChecksumOfOneAsset() {
        let list = "abc123  gh_1.0.0_macOS_arm64.zip\nDEF456  gh_1.0.0_macOS_amd64.zip\n"
        #expect(GhRelease.checksum(of: "gh_1.0.0_macOS_amd64.zip", in: list) == "def456")
        #expect(GhRelease.checksum(of: "gh_1.0.0_macOS_universal.pkg", in: list) == nil)
        #expect(GhRelease.archiveName(tag: "v2.3.4", architecture: "amd64") == "gh_2.3.4_macOS_amd64.zip")
        #expect(GhRelease.checksumsName(tag: "v2.3.4") == "gh_2.3.4_checksums.txt")
    }

    @Test func theRealSignatureCheckRejectsAnUnsignedExecutable() throws {
        let script = root.appending(path: "unsigned-gh")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: script)
        #expect(throws: GhInstallError.badSignature) { try GhSignature.check(script) }
    }
}
