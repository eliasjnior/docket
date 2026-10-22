import Foundation

/// `config.json`: what the user decided (`docs/04-data.md` §2.1). Never written by a poll.
public struct Config: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var selection: Selection
    public var polling: Polling
    public var count: Count
    public var notifications: Notifications
    public var reminders: Reminders
    public var ignored: [String: IgnoreEntry]
    public var botAllowlist: [String]
    public var ghPath: String?
    public var launchAtLogin: Bool?
    public var updates: Updates
    public var mutes: [String: MuteEntry]
    /// The global shortcut that opens the popover (FR-48); `off` disables it.
    public var shortcut: Shortcut
    public var triage: Triage
    /// How *Mine* is laid out: stacked sections or a board (spec §7).
    public var mineLayout: MineLayout
    public var integrations: Integrations

    public init(
        selection: Selection = Selection(), polling: Polling = Polling(), count: Count = Count(),
        notifications: Notifications = Notifications(), reminders: Reminders = Reminders(),
        ignored: [String: IgnoreEntry] = [:], botAllowlist: [String] = [], ghPath: String? = nil,
        launchAtLogin: Bool? = nil, updates: Updates = Updates(),
        mutes: [String: MuteEntry] = [:], shortcut: Shortcut = .controlOptionCommandD, triage: Triage = Triage(),
        mineLayout: MineLayout = .list, integrations: Integrations = Integrations()
    ) {
        version = Self.currentVersion
        self.selection = selection
        self.polling = polling
        self.count = count
        self.notifications = notifications
        self.reminders = reminders
        self.ignored = ignored
        self.botAllowlist = botAllowlist
        self.ghPath = ghPath
        self.launchAtLogin = launchAtLogin
        self.updates = updates
        self.mutes = mutes
        self.shortcut = shortcut
        self.triage = triage
        self.mineLayout = mineLayout
        self.integrations = integrations
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.value(.version, default: Self.currentVersion)
        selection = c.value(.selection, default: Selection())
        polling = c.value(.polling, default: Polling())
        count = c.value(.count, default: Count())
        notifications = c.value(.notifications, default: Notifications())
        reminders = c.value(.reminders, default: Reminders())
        ignored = c.value(.ignored, default: [:])
        botAllowlist = c.value(.botAllowlist, default: [])
        ghPath = c.value(.ghPath, default: nil)
        launchAtLogin = c.value(.launchAtLogin, default: nil)
        updates = c.value(.updates, default: Updates())
        mutes = c.value(.mutes, default: [:])
        shortcut = c.value(.shortcut, default: .controlOptionCommandD)
        triage = c.value(.triage, default: Triage())
        mineLayout = c.value(.mineLayout, default: .list)
        integrations = c.value(.integrations, default: Integrations())
    }

    /// *Open in Jira* and the AI actions (spec §9).
    public struct Integrations: Codable, Hashable, Sendable {
        public static let defaultReviewCommand =
            #"claude "Review the pull request {url}. Read the diff, the description and the review comments with gh. "#
            + #"Report bugs, risky changes and missing tests, citing file and line.""#
        public static let defaultSummarizeCommand =
            #"claude "Summarize the pull request {url} in a few sentences: what it changes and why. Read it with gh.""#

        public var jiraBaseURL: String?
        /// The terminal app's path; `nil` opens the script with the app macOS uses for `.command` files.
        public var terminalApp: String?
        public var reviewCommand: String
        public var summarizeCommand: String
        /// `owner/name` to a local clone the command runs in.
        public var clones: [String: String]

        public init(
            jiraBaseURL: String? = nil, terminalApp: String? = nil, reviewCommand: String = defaultReviewCommand,
            summarizeCommand: String = defaultSummarizeCommand, clones: [String: String] = [:]
        ) {
            self.jiraBaseURL = jiraBaseURL
            self.terminalApp = terminalApp
            self.reviewCommand = reviewCommand
            self.summarizeCommand = summarizeCommand
            self.clones = clones
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            jiraBaseURL = c.value(.jiraBaseURL, default: nil)
            terminalApp = c.value(.terminalApp, default: nil)
            reviewCommand = c.value(.reviewCommand, default: Self.defaultReviewCommand)
            summarizeCommand = c.value(.summarizeCommand, default: Self.defaultSummarizeCommand)
            clones = c.value(.clones, default: [:])
        }

        /// The clone of `repository`, matched case-insensitively.
        public func clone(of repository: String) -> String? {
            clones.first { $0.key.caseInsensitiveCompare(repository) == .orderedSame }?.value
        }
    }

    public enum MineLayout: String, Codable, Hashable, Sendable, CaseIterable {
        case list
        case board
    }

    public enum Shortcut: String, Codable, Hashable, Sendable, CaseIterable {
        case off
        case controlOptionCommandD
        case optionCommandD
        case controlOptionD
    }

    /// Reads a `config.json` exported from another install, through the same decoder as the file on disk
    /// (FR-96). A file from a newer Docket is refused rather than half-read.
    public static func imported(from data: Data) throws -> Config {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        struct Header: Decodable { var version: Int? }
        let header = try decoder.decode(Header.self, from: data)
        if let version = header.version, version > currentVersion {
            throw PersistenceError.newerVersion(file: "config.json", version: version)
        }
        return try decoder.decode(Config.self, from: data)
    }

    public func exported() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// How *Review requested* splits into Humans, Bots and Stale, and what the last two do outside the popover.
    public struct Triage: Codable, Hashable, Sendable {
        public static let allowedStaleDays = [3, 5, 7, 14, 30]
        public var staleAfterDays: Int
        /// Logins treated as bots although GitHub types them as users.
        public var extraBotLogins: [String]
        public var countBots: Bool
        public var countStale: Bool
        public var countDrafts: Bool

        public init(
            staleAfterDays: Int = 7, extraBotLogins: [String] = [], countBots: Bool = true, countStale: Bool = false,
            countDrafts: Bool = false
        ) {
            self.staleAfterDays = staleAfterDays
            self.extraBotLogins = extraBotLogins
            self.countBots = countBots
            self.countStale = countStale
            self.countDrafts = countDrafts
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let days = c.value(.staleAfterDays, default: 7)
            staleAfterDays = Self.allowedStaleDays.contains(days) ? days : 7
            extraBotLogins = c.value(.extraBotLogins, default: [])
            countBots = c.value(.countBots, default: true)
            countStale = c.value(.countStale, default: false)
            countDrafts = c.value(.countDrafts, default: false)
        }
    }

    public struct Polling: Codable, Hashable, Sendable {
        public static let allowedIntervals = [30, 60, 120, 300]
        public var intervalSeconds: Int

        public init(intervalSeconds: Int = 60) {
            self.intervalSeconds = intervalSeconds
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let value = c.value(.intervalSeconds, default: 60)
            intervalSeconds = Self.allowedIntervals.contains(value) ? value : 60
        }
    }

    public struct Count: Codable, Hashable, Sendable {
        public var includeReviewRequests: Bool
        public var includeBlockedAuthored: Bool

        public init(includeReviewRequests: Bool = true, includeBlockedAuthored: Bool = true) {
            self.includeReviewRequests = includeReviewRequests
            self.includeBlockedAuthored = includeBlockedAuthored
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            includeReviewRequests = c.value(.includeReviewRequests, default: true)
            includeBlockedAuthored = c.value(.includeBlockedAuthored, default: true)
        }
    }

    public struct Notifications: Codable, Hashable, Sendable {
        public var reviewRequested: Bool
        public var reviewSubmitted: Bool
        public var commentAdded: Bool
        public var threadReply: Bool
        public var checksFailed: Bool
        public var closedByOther: Bool
        public var mention: Bool

        public init(
            reviewRequested: Bool = true, reviewSubmitted: Bool = true, commentAdded: Bool = true,
            threadReply: Bool = true, checksFailed: Bool = true, closedByOther: Bool = true, mention: Bool = true
        ) {
            self.reviewRequested = reviewRequested
            self.reviewSubmitted = reviewSubmitted
            self.commentAdded = commentAdded
            self.threadReply = threadReply
            self.checksFailed = checksFailed
            self.closedByOther = closedByOther
            self.mention = mention
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            reviewRequested = c.value(.reviewRequested, default: true)
            reviewSubmitted = c.value(.reviewSubmitted, default: true)
            commentAdded = c.value(.commentAdded, default: true)
            threadReply = c.value(.threadReply, default: true)
            checksFailed = c.value(.checksFailed, default: true)
            closedByOther = c.value(.closedByOther, default: true)
            mention = c.value(.mention, default: true)
        }

        public func isEnabled(_ kind: EventKind) -> Bool {
            switch kind {
            case .reviewRequested: reviewRequested
            case .reviewSubmitted: reviewSubmitted
            case .commentAdded: commentAdded
            case .threadReply: threadReply
            case .checksFailed: checksFailed
            case .closedByOther: closedByOther
            case .mention: mention
            }
        }
    }

    public struct Reminders: Codable, Hashable, Sendable {
        public static let allowedIntervals = [15, 30, 60, 120, 240, 480]
        public var enabled: Bool
        public var intervalMinutes: Int
        public var quietHours: QuietHours

        public init(enabled: Bool = true, intervalMinutes: Int = 60, quietHours: QuietHours = QuietHours()) {
            self.enabled = enabled
            self.intervalMinutes = intervalMinutes
            self.quietHours = quietHours
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = c.value(.enabled, default: true)
            let minutes = c.value(.intervalMinutes, default: 60)
            intervalMinutes = Self.allowedIntervals.contains(minutes) ? minutes : 60
            quietHours = c.value(.quietHours, default: QuietHours())
        }

        public var interval: TimeInterval { TimeInterval(intervalMinutes * 60) }
    }

    public struct QuietHours: Codable, Hashable, Sendable {
        public var enabled: Bool
        /// `HH:mm`, local time.
        public var start: String
        public var end: String

        public init(enabled: Bool = false, start: String = "22:00", end: String = "08:00") {
            self.enabled = enabled
            self.start = start
            self.end = end
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = c.value(.enabled, default: false)
            start = c.value(.start, default: "22:00")
            end = c.value(.end, default: "08:00")
        }
    }

    public struct Updates: Codable, Hashable, Sendable {
        public var automaticChecks: Bool
        public var automaticInstall: Bool

        public init(automaticChecks: Bool = true, automaticInstall: Bool = false) {
            self.automaticChecks = automaticChecks
            self.automaticInstall = automaticInstall
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            automaticChecks = c.value(.automaticChecks, default: true)
            automaticInstall = c.value(.automaticInstall, default: false)
        }
    }

    public struct MuteEntry: Codable, Hashable, Sendable {
        public enum Scope: String, Codable, Hashable, Sendable {
            case reminders
            case all
        }

        public var ref: String
        public var scope: Scope
        public var mutedAt: Date

        public init(ref: String, scope: Scope, mutedAt: Date) {
            self.ref = ref
            self.scope = scope
            self.mutedAt = mutedAt
        }
    }

    public struct IgnoreEntry: Codable, Hashable, Sendable {
        public var ref: String
        public var ignoredAt: Date

        public init(ref: String, ignoredAt: Date) {
            self.ref = ref
            self.ignoredAt = ignoredAt
        }
    }
}
