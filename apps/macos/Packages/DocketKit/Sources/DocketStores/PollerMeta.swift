import DocketCore
import Foundation

extension Poller {
    static func combine(_ metas: [ResponseMeta]) -> ResponseMeta {
        var combined = ResponseMeta()
        var cost = 0
        for meta in metas {
            if let rateLimit = meta.rateLimit {
                cost += rateLimit.cost
                combined.rateLimit = rateLimit
            }
            combined.serverDate = meta.serverDate ?? combined.serverDate
            combined.samlURL = meta.samlURL ?? combined.samlURL
            combined.samlOrganizations.append(contentsOf: meta.samlOrganizations)
        }
        combined.rateLimit?.cost = cost
        combined.samlOrganizations = Array(Set(combined.samlOrganizations)).sorted()
        return combined
    }

    static func samlOrganizations(_ meta: ResponseMeta) -> [SAMLOrganization] {
        var organizations = meta.samlOrganizations.compactMap { login in
            URL(string: "https://github.com/orgs/\(login)/sso").map { SAMLOrganization(login: login, url: $0) }
        }
        if let url = meta.samlURL {
            let parts = url.pathComponents
            if let index = parts.firstIndex(of: "orgs"), index + 1 < parts.count {
                let login = parts[index + 1]
                organizations.removeAll { $0.login == login }
                organizations.append(SAMLOrganization(login: login, url: url))
            }
        }
        return organizations.sorted { $0.login < $1.login }
    }
}
