import Foundation

/// Reads releases of one component from the GitHub REST API, with the `gh` token while the repository is
/// private (D-14).
public struct GitHubReleasesSource: ReleaseSource {
    private let repository: String
    private let tagPrefix: String
    private let session: URLSession
    private let token: @Sendable () async -> String?
    private let api = URL(string: "https://api.github.com") ?? URL(fileURLWithPath: "/")

    public init(
        repository: String, tagPrefix: String = "macos-v", session: URLSession = .shared,
        token: @escaping @Sendable () async -> String?
    ) {
        self.repository = repository
        self.tagPrefix = tagPrefix
        self.session = session
        self.token = token
    }

    public func latest(after current: SemanticVersion) async throws -> AvailableUpdate? {
        let url = api.appending(path: "repos/\(repository)/releases").appending(queryItems: [
            URLQueryItem(name: "per_page", value: "30")
        ])
        let releases = try await send([GitHubRelease].self, url: url, accept: "application/vnd.github+json")
        let candidates =
            releases
            .filter { !$0.draft && !$0.prerelease && $0.tagName.hasPrefix(tagPrefix) }
            .compactMap { release in SemanticVersion(release.tagName).map { (release, $0) } }
            .filter { $0.1 > current }
            .sorted { $0.1 > $1.1 }
        guard let (release, version) = candidates.first else { return nil }
        guard let manifestAsset = release.assets.first(where: { $0.name == "release.json" }) else {
            throw UpdateError.missingAsset("release.json")
        }
        let manifest = try await send(ReleaseManifest.self, url: manifestAsset.url, accept: "application/octet-stream")
        guard let archive = release.assets.first(where: { $0.name == manifest.asset }) else {
            throw UpdateError.missingAsset(manifest.asset)
        }
        return AvailableUpdate(
            version: version, notes: release.body ?? "", publishedAt: release.publishedAt, manifest: manifest,
            archiveURL: archive.url)
    }

    public func downloadArchive(of update: AvailableUpdate, to directory: URL) async throws -> URL {
        let data = try await fetch(update.archiveURL, accept: "application/octet-stream")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: update.manifest.asset)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private func send<T: Decodable>(_ type: T.Type, url: URL, accept: String) async throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try await fetch(url, accept: accept)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw UpdateError.invalidBundle("Unreadable release data")
        }
    }

    private func fetch(_ url: URL, accept: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 60
        if let token = await token(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return data
        // A private repository answers 404, not 401, to requests without a valid token.
        case 401, 403, 404: throw UpdateError.unauthorized
        default: throw UpdateError.installFailed("GitHub answered \(status)")
        }
    }
}

struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let url: URL
    }

    let tagName: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let publishedAt: Date?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case draft
        case prerelease
        case publishedAt = "published_at"
        case assets
    }
}
