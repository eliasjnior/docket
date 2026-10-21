import Foundation

public enum PullRequestState: String, Codable, Hashable, Sendable {
    case open = "OPEN"
    case closed = "CLOSED"
    case merged = "MERGED"
}

public enum Mergeable: String, Codable, Hashable, Sendable {
    case mergeable = "MERGEABLE"
    case conflicting = "CONFLICTING"
    case unknown = "UNKNOWN"
}

/// `statusCheckRollup.state` of the head commit.
public enum CheckState: String, Codable, Hashable, Sendable {
    case success = "SUCCESS"
    case failure = "FAILURE"
    case error = "ERROR"
    case pending = "PENDING"
    case expected = "EXPECTED"
}

public enum ReviewDecision: String, Codable, Hashable, Sendable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
}

public enum ReviewState: String, Codable, Hashable, Sendable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case commented = "COMMENTED"
    case pending = "PENDING"
    case dismissed = "DISMISSED"
}
