import DocketCore
import Foundation
import Testing

struct ConfigTests {
    private func decode(_ json: String) throws -> Config {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Config.self, from: Data(json.utf8))
    }

    @Test func decodesTheDocumentedExample() throws {
        let config = try decode(
            """
            {
              "botAllowlist": ["copilot-pull-request-reviewer"],
              "count": { "includeBlockedAuthored": true, "includeReviewRequests": true },
              "ghPath": null,
              "ignored": {},
              "launchAtLogin": true,
              "mutes": {
                "PR_kwDOAbc456": { "mutedAt": "2026-10-20T09:12:00Z", "ref": "acme/web#91", "scope": "reminders" }
              },
              "notifications": { "commentAdded": true, "reviewRequested": true, "reviewSubmitted": true },
              "polling": { "intervalSeconds": 60 },
              "reminders": {
                "enabled": true,
                "intervalMinutes": 60,
                "quietHours": { "enabled": false, "end": "08:00", "start": "22:00" }
              },
              "selection": {
                "excludedOwners": [],
                "excludedRepositories": ["acme/legacy-monolith"],
                "includedOwners": [],
                "includedRepositories": [],
                "mode": "all"
              },
              "tags": {
                "PR_kwDOAbc123": { "ref": "acme/api#482", "tags": ["wip"], "updatedAt": "2026-10-21T14:03:00Z" }
              },
              "updates": { "automaticChecks": true, "automaticInstall": false },
              "version": 1
            }
            """)
        #expect(config.botAllowlist == ["copilot-pull-request-reviewer"])
        #expect(config.mutes["PR_kwDOAbc456"]?.scope == .reminders)
        // A file from before labels replaced tags still decodes; its tags are ignored.
        #expect(config.mutes.count == 1)
        #expect(config.selection.excludedRepositories == ["acme/legacy-monolith"])
        #expect(config.launchAtLogin == true)
        #expect(config.ghPath == nil)
        #expect(config.notifications.threadReply)
    }

    @Test func missingFieldsTakeTheirDefaults() throws {
        let config = try decode(#"{ "version": 1, "polling": {} }"#)
        #expect(config == Config())
    }

    @Test func valuesOutsideTheAllowedSetFallBack() throws {
        let config = try decode(#"{ "polling": { "intervalSeconds": 7 }, "reminders": { "intervalMinutes": 5 } }"#)
        #expect(config.polling.intervalSeconds == 60)
        #expect(config.reminders.intervalMinutes == 60)
    }

    @Test func aFieldOfTheWrongTypeLosesOnlyThatField() throws {
        let config = try decode(#"{ "botAllowlist": "nope", "ghPath": "/opt/gh" }"#)
        #expect(config.botAllowlist.isEmpty)
        #expect(config.ghPath == "/opt/gh")
    }

    @Test func roundTrips() throws {
        var config = Config()
        config.mutes["PR_1"] = Config.MuteEntry(
            ref: "acme/api#1", scope: .all, mutedAt: Date(timeIntervalSince1970: 0))
        config.selection.mode = .only
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(Config.self, from: encoder.encode(config)) == config)
    }

    @Test(arguments: [
        (EventKind.reviewRequested, true), (.reviewSubmitted, false), (.commentAdded, true), (.threadReply, true),
    ])
    func notificationToggles(kind: EventKind, enabled: Bool) {
        let notifications = Config.Notifications(reviewSubmitted: false)
        #expect(notifications.isEnabled(kind) == enabled)
    }
}

struct ExportImportTests {
    @Test("M5 Done when: an exported config restores selection and mutes on a fresh install")
    func roundTrip() throws {
        var config = Config(selection: Selection(mode: .only, includedRepositories: ["acme/api"]))
        config.mutes["PR_1"] = Config.MuteEntry(
            ref: "acme/api#482", scope: .reminders, mutedAt: Date(timeIntervalSince1970: 1_792_584_000))
        config.triage.extraBotLogins = ["renovate"]
        config.mineLayout = .board
        config.shortcut = .optionCommandD
        #expect(try Config.imported(from: config.exported()) == config)
    }

    @Test func aNewerExportIsRefused() {
        #expect(throws: PersistenceError.newerVersion(file: "config.json", version: 4)) {
            try Config.imported(from: Data(#"{"version": 4}"#.utf8))
        }
        #expect(throws: (any Error).self) { try Config.imported(from: Data("not json".utf8)) }
    }

    @Test func theShortcutDefaultsAndToleratesUnknownValues() throws {
        #expect(Config().shortcut == .controlOptionCommandD)
        #expect(try Config.imported(from: Data(#"{"shortcut": "hyperD"}"#.utf8)).shortcut == .controlOptionCommandD)
    }
}
