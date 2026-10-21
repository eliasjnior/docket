import AppIntents

/// Docket's Focus filter (`docs/02-activity-detection.md` §7.5, D-25). macOS runs it with the configured value
/// when a Focus that has it turns on, and with the default when that Focus ends.
struct DocketFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = LocalizedStringResource("Docket", comment: "Focus filter title")
    static let description: IntentDescription? = IntentDescription(
        LocalizedStringResource(
            "Hold Docket's notifications until this Focus ends, then deliver one summary per repository.",
            comment: "Focus filter description"))

    @Parameter(
        title: LocalizedStringResource("Hold notifications until this Focus ends", comment: "Focus filter parameter"),
        default: false)
    var hold: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: hold
                ? LocalizedStringResource("Holding notifications", comment: "Focus filter summary")
                : LocalizedStringResource("Not holding notifications", comment: "Focus filter summary"))
    }

    func perform() async throws -> some IntentResult {
        await FocusBridge.deliver(hold)
        return .result()
    }
}

/// Hands the filter's value to the running app; a value that arrives before launch finishes is kept.
@MainActor
enum FocusBridge {
    private static var handler: ((Bool) async -> Void)?
    private static var pending: Bool?

    static func deliver(_ hold: Bool) async {
        if let handler {
            await handler(hold)
        } else {
            pending = hold
        }
    }

    static func connect(_ handler: @escaping (Bool) async -> Void) async {
        self.handler = handler
        if let pending {
            self.pending = nil
            await handler(pending)
        }
    }
}
