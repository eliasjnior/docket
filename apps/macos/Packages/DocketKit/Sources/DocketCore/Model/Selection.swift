import Foundation

/// Which repositories are watched (`docs/02-activity-detection.md` §2.3).
public struct Selection: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Hashable, Sendable {
        case all
        case only
    }

    public var mode: Mode
    public var includedRepositories: [String]
    public var includedOwners: [String]
    public var excludedRepositories: [String]
    public var excludedOwners: [String]

    public init(
        mode: Mode = .all, includedRepositories: [String] = [], includedOwners: [String] = [],
        excludedRepositories: [String] = [], excludedOwners: [String] = []
    ) {
        self.mode = mode
        self.includedRepositories = includedRepositories
        self.includedOwners = includedOwners
        self.excludedRepositories = excludedRepositories
        self.excludedOwners = excludedOwners
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = c.value(.mode, default: .all)
        includedRepositories = c.value(.includedRepositories, default: [])
        includedOwners = c.value(.includedOwners, default: [])
        excludedRepositories = c.value(.excludedRepositories, default: [])
        excludedOwners = c.value(.excludedOwners, default: [])
    }

    public func watches(_ repository: String) -> Bool {
        let name = repository.lowercased()
        let owner = String(name.split(separator: "/").first ?? "")
        func contains(_ list: [String], _ value: String) -> Bool { list.contains { $0.lowercased() == value } }
        switch mode {
        case .all:
            return !contains(excludedRepositories, name) && !contains(excludedOwners, owner)
        case .only:
            return contains(includedRepositories, name) || contains(includedOwners, owner)
        }
    }
}
