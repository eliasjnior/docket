import Foundation

public struct ReleaseManifest: Codable, Equatable, Sendable {
    public let version: SemanticVersion
    public let build: String
    public let asset: String
    public let signature: String
    public let size: Int
    public let minimumSystemVersion: String
}

public struct AvailableUpdate: Equatable, Sendable, Identifiable {
    public let version: SemanticVersion
    public let notes: String
    public let publishedAt: Date?
    public let manifest: ReleaseManifest
    public let archiveURL: URL

    public var id: SemanticVersion { version }

    public init(version: SemanticVersion, notes: String, publishedAt: Date?, manifest: ReleaseManifest, archiveURL: URL)
    {
        self.version = version
        self.notes = notes
        self.publishedAt = publishedAt
        self.manifest = manifest
        self.archiveURL = archiveURL
    }
}

public enum UpdateError: Error, Equatable, Sendable {
    case unauthorized
    case missingAsset(String)
    case badSignature
    case sizeMismatch
    case invalidBundle(String)
    case requirementMismatch
    case unsupportedSystem(String)
    case installFailed(String)
}

public protocol ReleaseSource: Sendable {
    /// The newest published release strictly newer than `current`, if any.
    func latest(after current: SemanticVersion) async throws -> AvailableUpdate?
    func downloadArchive(of update: AvailableUpdate, to directory: URL) async throws -> URL
}
