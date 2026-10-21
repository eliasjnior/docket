import Foundation

/// Why a pull request is watched, by precedence (D-08).
public enum Role: String, Codable, Hashable, Sendable, CaseIterable {
    case authored
    case reviewRequested
    case involved
}
