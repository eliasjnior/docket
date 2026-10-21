import DocketCore
import Foundation
import Testing

struct ModelTests {
    @Test func statusesSortInPrecedenceOrder() {
        #expect(Status.allCases.sorted() == Status.allCases)
        #expect(Status.conflict < .noReviewers)
    }

    @Test(arguments: [
        ("dependabot[bot]", false, true), ("copilot-pull-request-reviewer", true, true), ("ana", false, false),
    ])
    func botsAreRecognizedByTypeOrSuffix(login: String, isBot: Bool, expected: Bool) {
        #expect(Actor(login: login, isBot: isBot).isAnyBot == expected)
    }

    @Test func reviewerHandles() {
        #expect(Reviewer.user(login: "ana").handle == "@ana")
        #expect(Reviewer.team(organization: "acme", slug: "backend").handle == "@acme/backend")
    }

    @Test(arguments: [
        (Selection.Mode.all, "acme/api", true), (.all, "ACME/Legacy", false), (.all, "corp/x", false),
        (.only, "acme/api", false), (.only, "Acme/Web", true), (.only, "tools/cli", true),
    ])
    func selectionIsCaseInsensitive(mode: Selection.Mode, repository: String, watched: Bool) {
        let selection = Selection(
            mode: mode, includedRepositories: ["acme/web"], includedOwners: ["tools"],
            excludedRepositories: ["acme/legacy"], excludedOwners: ["corp"]
        )
        #expect(selection.watches(repository) == watched)
    }

    @Test func cursorKeepsTheNewest500Seen() {
        var cursor = Cursor(ref: "acme/api#1", role: .authored, updatedAt: .distantPast, enteredAt: .distantPast)
        cursor.markSeen((0..<480).map { "a\($0)" })
        cursor.markSeen((0..<40).map { "b\($0)" } + ["a0"])
        #expect(cursor.seen.count == 500)
        #expect(cursor.seen.first == "a20")
        #expect(cursor.seen.last == "b39")
    }

    @Test func discoveryDeduplicatesInOrder() {
        let discovery = Discovery(authored: ["1", "2"], requested: ["2", "3"], commented: ["1"], reviewed: ["4"])
        #expect(discovery.allIDs == ["1", "2", "3", "4"])
    }

    @Test func eventIDsAreKindAndItem() throws {
        let event = Event(
            kind: .reviewSubmitted, itemID: "PRR_1", pullRequestID: "PR_1", repository: "acme/api", number: 470,
            title: "t", url: try #require(URL(string: "https://github.com/acme/api/pull/470")), actor: "ana",
            at: .distantPast
        )
        #expect(event.id == "reviewSubmitted:PRR_1")
        #expect(HeldEvent(event).ref == "acme/api#470")
        #expect(HeldEvent(event).repository == "acme/api")
        #expect(HeldEvent(event).number == 470)
    }

    @Test func stateRoundTripsAndToleratesMissingFields() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let empty = try decoder.decode(PersistedState.self, from: Data("{}".utf8))
        #expect(empty == PersistedState())
        var state = PersistedState(viewerLogin: "you", baselineAt: Date(timeIntervalSince1970: 100))
        state.reminders["PR_1"] = ReminderRecord(requestedAt: Date(timeIntervalSince1970: 50), lastRemindedAt: nil)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        #expect(try decoder.decode(PersistedState.self, from: encoder.encode(state)) == state)
    }
}
