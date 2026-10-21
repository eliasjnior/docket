import Foundation

public struct AppInfo: Sendable, Equatable {
    public let version: String
    public let build: String

    public init(version: String, build: String) {
        self.version = version
        self.build = build
    }

    public init(bundle: Bundle) {
        self.init(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        )
    }

    public var displayVersion: String { "\(version) (\(build))" }
    public var semanticVersion: SemanticVersion {
        SemanticVersion(version) ?? SemanticVersion(major: 0, minor: 0, patch: 0)
    }
}

public struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible, Codable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Accepts `1.2.3`, `v1.2.3` and component-prefixed tags such as `macos-v1.2.3`.
    public init?(_ string: String) {
        let trimmed = string.split(separator: "v").last.map(String.init) ?? string
        let core = trimmed.split(separator: "-").first.map(String.init) ?? trimmed
        let parts = core.split(separator: ".").map { Int($0) }
        guard parts.count == 3, let major = parts[0], let minor = parts[1], let patch = parts[2] else { return nil }
        self.init(major: major, minor: minor, patch: patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let version = SemanticVersion(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a version: \(raw)")
        }
        self = version
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
