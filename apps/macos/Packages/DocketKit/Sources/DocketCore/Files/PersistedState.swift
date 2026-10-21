import Foundation

/// `state.json`: what the app decided (`docs/04-data.md` §2.2). Losing it costs one fresh baseline.
public struct PersistedState: Codable, Hashable, Sendable {
    public static let currentVersion = 1
    public static let heldLimit = 500

    public var version: Int
    public var viewerLogin: String?
    public var baselineAt: Date?
    public var cursors: [String: Cursor]
    public var delivered: [String: Date]
    public var reminders: [String: ReminderRecord]
    public var focusHold: FocusHold?
    public var held: [HeldEvent]
    public var marked: [String]
    public var popoverOpenedAt: Date?
    public var teams: [String: TeamCache]
    public var unauthorizedOwners: [String]
    public var lastPoll: LastPoll?
    public var lastShownVersion: String?
    public var skippedVersion: String?
    public var lastUpdateCheckAt: Date?
    public var baselineNoticeDismissed: Bool

    public init(
        viewerLogin: String? = nil, baselineAt: Date? = nil, cursors: [String: Cursor] = [:],
        delivered: [String: Date] = [:], reminders: [String: ReminderRecord] = [:], focusHold: FocusHold? = nil,
        held: [HeldEvent] = [], marked: [String] = [], popoverOpenedAt: Date? = nil,
        teams: [String: TeamCache] = [:], unauthorizedOwners: [String] = [], lastPoll: LastPoll? = nil,
        lastShownVersion: String? = nil, skippedVersion: String? = nil, lastUpdateCheckAt: Date? = nil,
        baselineNoticeDismissed: Bool = false
    ) {
        version = Self.currentVersion
        self.viewerLogin = viewerLogin
        self.baselineAt = baselineAt
        self.cursors = cursors
        self.delivered = delivered
        self.reminders = reminders
        self.focusHold = focusHold
        self.held = held
        self.marked = marked
        self.popoverOpenedAt = popoverOpenedAt
        self.teams = teams
        self.unauthorizedOwners = unauthorizedOwners
        self.lastPoll = lastPoll
        self.lastShownVersion = lastShownVersion
        self.skippedVersion = skippedVersion
        self.lastUpdateCheckAt = lastUpdateCheckAt
        self.baselineNoticeDismissed = baselineNoticeDismissed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.value(.version, default: Self.currentVersion)
        viewerLogin = c.value(.viewerLogin, default: nil)
        baselineAt = c.value(.baselineAt, default: nil)
        cursors = c.value(.cursors, default: [:])
        delivered = c.value(.delivered, default: [:])
        reminders = c.value(.reminders, default: [:])
        focusHold = c.value(.focusHold, default: nil)
        held = c.value(.held, default: [])
        marked = c.value(.marked, default: [])
        popoverOpenedAt = c.value(.popoverOpenedAt, default: nil)
        teams = c.value(.teams, default: [:])
        unauthorizedOwners = c.value(.unauthorizedOwners, default: [])
        lastPoll = c.value(.lastPoll, default: nil)
        lastShownVersion = c.value(.lastShownVersion, default: nil)
        skippedVersion = c.value(.skippedVersion, default: nil)
        lastUpdateCheckAt = c.value(.lastUpdateCheckAt, default: nil)
        baselineNoticeDismissed = c.value(.baselineNoticeDismissed, default: false)
    }
}

/// When a review request was made and when it was last reminded (`docs/02-activity-detection.md` §5.7).
public struct ReminderRecord: Codable, Hashable, Sendable {
    public var requestedAt: Date
    public var lastRemindedAt: Date?

    public init(requestedAt: Date, lastRemindedAt: Date?) {
        self.requestedAt = requestedAt
        self.lastRemindedAt = lastRemindedAt
    }
}

public struct FocusHold: Codable, Hashable, Sendable {
    public var since: Date

    public init(since: Date) {
        self.since = since
    }
}

/// An event committed during a Focus hold, awaiting the digest (`docs/02-activity-detection.md` §7.5).
public struct HeldEvent: Codable, Hashable, Sendable {
    public var eventID: String
    public var kind: EventKind
    public var nodeID: String
    public var ref: String
    public var actor: String?
    public var decision: ReviewState?
    public var at: Date

    public init(
        eventID: String, kind: EventKind, nodeID: String, ref: String, actor: String?, decision: ReviewState?,
        at: Date
    ) {
        self.eventID = eventID
        self.kind = kind
        self.nodeID = nodeID
        self.ref = ref
        self.actor = actor
        self.decision = decision
        self.at = at
    }

    public init(_ event: Event) {
        self.init(
            eventID: event.id, kind: event.kind, nodeID: event.pullRequestID,
            ref: "\(event.repository)#\(event.number)", actor: event.actor, decision: event.decision, at: event.at
        )
    }

    public var repository: String { String(ref.split(separator: "#").first ?? "") }
    public var number: Int { Int(ref.split(separator: "#").last ?? "") ?? 0 }
}

public struct TeamCache: Codable, Hashable, Sendable {
    public var slugs: [String]
    public var fetchedAt: Date

    public init(slugs: [String], fetchedAt: Date) {
        self.slugs = slugs
        self.fetchedAt = fetchedAt
    }
}

/// The rate budget and clock offset of the last poll (`docs/02-activity-detection.md` §3.4, §6.3).
public struct LastPoll: Codable, Hashable, Sendable {
    public var at: Date
    public var cost: Int
    public var remaining: Int
    public var limit: Int
    public var resetAt: Date?
    /// Server time minus the Mac's clock, in seconds.
    public var serverTimeOffset: TimeInterval

    public init(at: Date, cost: Int, remaining: Int, limit: Int, resetAt: Date?, serverTimeOffset: TimeInterval) {
        self.at = at
        self.cost = cost
        self.remaining = remaining
        self.limit = limit
        self.resetAt = resetAt
        self.serverTimeOffset = serverTimeOffset
    }
}
