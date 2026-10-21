import DocketCore
import Foundation

/// Who "you" are for one poll: your login and the teams you belong to.
public struct ViewerContext: Hashable, Sendable {
    public var login: String
    /// Team slugs per organization login, lower-cased. `nil` without `read:org` (`docs/02-activity-detection.md` §2.2).
    public var teams: [String: Set<String>]?

    public init(login: String, teams: [String: Set<String>]? = [:]) {
        self.login = login
        self.teams = teams
    }

    public func isYou(_ login: String?) -> Bool {
        guard let login else { return false }
        return login.caseInsensitiveCompare(self.login) == .orderedSame
    }

    /// Whether a request to `reviewer` is a request to you. `nil` when it is a team and the teams are unknown.
    public func isAddressedToYou(_ reviewer: Reviewer?) -> Bool? {
        switch reviewer {
        case .user(let login): isYou(login)
        case .team(let organization, let slug):
            teams.map { $0[organization.lowercased()]?.contains(slug.lowercased()) ?? false }
        case nil: false
        }
    }
}
