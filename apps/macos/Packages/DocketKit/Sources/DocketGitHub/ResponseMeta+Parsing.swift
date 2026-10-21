import DocketCore
import Foundation

extension ResponseMeta {
    static func parse(_ response: HTTPURLResponse) -> ResponseMeta {
        var meta = ResponseMeta()
        if let date = response.value(forHTTPHeaderField: "Date") {
            meta.serverDate = httpDateFormatter.date(from: date)
        }
        if let scopes = response.value(forHTTPHeaderField: "X-OAuth-Scopes") {
            meta.scopes = scopes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        if let sso = response.value(forHTTPHeaderField: "X-GitHub-SSO") {
            let parts = sso.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            for part in parts {
                if part.hasPrefix("url=") {
                    meta.samlURL = URL(string: String(part.dropFirst(4)))
                } else if part.hasPrefix("organizations=") {
                    meta.samlOrganizations = part.dropFirst("organizations=".count).split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                }
            }
        }
        return meta
    }

    func with(_ rateLimit: RateLimitDTO?) -> ResponseMeta {
        var copy = self
        if let rateLimit { copy.rateLimit = rateLimit.value }
        return copy
    }

    /// Costs add up; everything else is the latest response's.
    func merged(_ next: ResponseMeta) -> ResponseMeta {
        var merged = next
        if let previous = rateLimit, let latest = next.rateLimit {
            merged.rateLimit = RateLimit(
                cost: previous.cost + latest.cost, remaining: latest.remaining, limit: latest.limit,
                resetAt: latest.resetAt)
        } else if next.rateLimit == nil {
            merged.rateLimit = rateLimit
        }
        merged.serverDate = next.serverDate ?? serverDate
        merged.scopes = next.scopes ?? scopes
        merged.samlOrganizations = Array(Set(samlOrganizations + next.samlOrganizations)).sorted()
        merged.samlURL = next.samlURL ?? samlURL
        return merged
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}

extension ResponseMeta {
    /// Combines the metadata of every request in one poll.
    public static func combine(_ metas: [ResponseMeta]) -> ResponseMeta {
        metas.reduce(ResponseMeta()) { $0.merged($1) }
    }
}
