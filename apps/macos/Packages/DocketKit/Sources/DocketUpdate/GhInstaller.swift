import CryptoKit
import Foundation
import Security

/// Installs the GitHub CLI on a Mac that has none (FR-15).
public protocol GhInstalling: Sendable {
    /// Returns the installed `gh`.
    func install() async throws -> URL
}

public enum GhInstallError: Error, Hashable, Sendable {
    /// GitHub answered with this status, or `0` when it did not answer.
    case unavailable(Int)
    case missingAsset(String)
    case checksumMismatch
    case badSignature
    case unpackFailed
}

/// The latest `cli/cli` release for this Mac's architecture, checked against the release's own SHA-256 list
/// and GitHub's code signature, into Docket's folder: no Homebrew, no administrator password, and no host but
/// GitHub's (NFR-10). The repository is public, so no token is sent; there may be none yet.
public struct GhInstaller: GhInstalling {
    private let destination: URL
    private let session: URLSession
    private let architecture: String
    private let workDirectory: URL
    private let checkSignature: @Sendable (URL) throws -> Void
    private let latest =
        URL(string: "https://api.github.com/repos/cli/cli/releases/latest") ?? URL(fileURLWithPath: "/")

    public init(
        destination: URL, session: URLSession = .shared, architecture: String = GhRelease.currentArchitecture,
        workDirectory: URL = FileManager.default.temporaryDirectory.appending(path: "DocketGh"),
        checkSignature: @escaping @Sendable (URL) throws -> Void = GhSignature.check
    ) {
        self.destination = destination
        self.session = session
        self.architecture = architecture
        self.workDirectory = workDirectory
        self.checkSignature = checkSignature
    }

    public func install() async throws -> URL {
        let release: GitHubRelease
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            release = try decoder.decode(
                GitHubRelease.self, from: try await fetch(latest, accept: "application/vnd.github+json"))
        } catch let error as GhInstallError {
            throw error
        } catch {
            throw GhInstallError.unavailable(0)
        }
        let archiveName = GhRelease.archiveName(tag: release.tagName, architecture: architecture)
        let checksumsName = GhRelease.checksumsName(tag: release.tagName)
        guard let archive = release.assets.first(where: { $0.name == archiveName }) else {
            throw GhInstallError.missingAsset(archiveName)
        }
        guard let checksums = release.assets.first(where: { $0.name == checksumsName }) else {
            throw GhInstallError.missingAsset(checksumsName)
        }
        let list =
            String(bytes: try await fetch(checksums.url, accept: "application/octet-stream"), encoding: .utf8) ?? ""
        guard let expected = GhRelease.checksum(of: archiveName, in: list) else {
            throw GhInstallError.missingAsset(checksumsName)
        }
        let data = try await fetch(archive.url, accept: "application/octet-stream")
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expected else {
            throw GhInstallError.checksumMismatch
        }
        let work = workDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: work) }
        let executable = try unpack(data, named: archiveName, into: work)
        try checkSignature(executable)
        try place(executable)
        return destination
    }

    private func unpack(_ data: Data, named name: String, into work: URL) throws -> URL {
        let zip = work.appending(path: name)
        let unpacked = work.appending(path: "unpacked", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
            try data.write(to: zip)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", zip.path, unpacked.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw GhInstallError.unpackFailed }
        } catch {
            throw GhInstallError.unpackFailed
        }
        let executable = unpacked.appending(path: String(name.dropLast(".zip".count))).appending(path: "bin/gh")
        guard FileManager.default.fileExists(atPath: executable.path) else { throw GhInstallError.unpackFailed }
        return executable
    }

    private func place(_ executable: URL) throws {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
            try manager.moveItem(at: executable, to: destination)
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        } catch {
            throw GhInstallError.unpackFailed
        }
    }

    private func fetch(_ url: URL, accept: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 120
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GhInstallError.unavailable(0)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw GhInstallError.unavailable(status) }
        return data
    }
}

/// The names `cli/cli` gives its release assets, and its checksum list.
public enum GhRelease {
    public static var currentArchitecture: String {
        #if arch(arm64)
            "arm64"
        #else
            "amd64"
        #endif
    }

    static func archiveName(tag: String, architecture: String) -> String {
        "gh_\(version(tag))_macOS_\(architecture).zip"
    }

    static func checksumsName(tag: String) -> String { "gh_\(version(tag))_checksums.txt" }

    /// The lowercase SHA-256 of `name` in a `<hex>  <name>` list.
    static func checksum(of name: String, in list: String) -> String? {
        list.split(whereSeparator: \.isNewline).lazy
            .map { $0.split(whereSeparator: \.isWhitespace) }
            .first { $0.count == 2 && $0[1] == name }
            .map { $0[0].lowercased() }
    }

    private static func version(_ tag: String) -> String { tag.hasPrefix("v") ? String(tag.dropFirst()) : tag }
}

/// `gh` must carry GitHub's Developer ID signature, so a tampered release is refused even with a matching
/// checksum list.
public enum GhSignature {
    static let teamIdentifier = "VEKTX9H2N7"

    public static func check(_ executable: URL) throws {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let text = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        guard SecStaticCodeCreateWithPath(executable as CFURL, [], &code) == errSecSuccess, let code,
            SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement,
            SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement)
                == errSecSuccess
        else {
            throw GhInstallError.badSignature
        }
    }
}
