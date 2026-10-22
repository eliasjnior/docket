import AppKit
import DocketActivity
import DocketCore
import DocketStores
import SwiftUI

/// `Docket --snapshot <directory>` renders views with synthetic data to PNG, light and dark, then exits
/// (`docs/03-architecture.md` §8), so a view can be checked without screen capture.
@MainActor
enum Snapshots {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(flag + 1) else { return }
        let directory = URL(fileURLWithPath: arguments[flag + 1])
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scenarios = [
            Scenario(name: "popover", account: .ready, cache: SampleData.cache),
            Scenario(name: "popover-bots", account: .ready, cache: SampleData.cache, triage: .bots),
            Scenario(name: "popover-stale", account: .ready, cache: SampleData.cache, triage: .stale),
            Scenario(
                name: "popover-filters", account: .ready, cache: SampleData.cache,
                filter: PopoverFilter(organizations: ["acme", "globex"], labels: ["backend"])),
            Scenario(name: "popover-mine", account: .ready, cache: SampleData.cache, tab: .mine),
            Scenario(name: "popover-mine-board", account: .ready, cache: SampleData.cache, tab: .mine, board: true),
            Scenario(name: "popover-involved", account: .ready, cache: SampleData.cache, tab: .involved),
            Scenario(name: "popover-offline", account: .ready, problem: .offline, cache: SampleData.cache),
            Scenario(
                name: "popover-empty", account: .ready,
                cache: SnapshotCache(fetchedAt: SampleData.now, viewerLogin: "you")),
            Scenario(name: "gh-not-found", account: .ghNotFound),
            Scenario(name: "signed-out", account: .signedOut),
            Scenario(name: "missing-scopes", account: .missingScopes(["read:org"])),
            Scenario(name: "loading", account: .loading),
        ]
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            for scenario in scenarios {
                let watch = SampleData.watch(
                    account: scenario.account, problem: scenario.problem, cache: scenario.cache,
                    board: scenario.board)
                let model = PopoverModel()
                model.tab = scenario.tab
                model.triage = scenario.triage
                model.filter = scenario.filter
                render(
                    PopoverView(
                        watch: watch, model: model, permission: NotificationPermission(), actions: SampleData.actions),
                    appearance: appearance, to: directory, name: "\(scenario.name)-\(suffix)")
            }
            renderSettings(appearance: appearance, to: directory, suffix: suffix)
        }
        exit(0)
    }

    private static func renderSettings(appearance: NSAppearance.Name, to directory: URL, suffix: String) {
        let watch = SampleData.watch(account: .ready, problem: nil, cache: SampleData.cache)
        let configStore = watch.configStore
        render(
            NotificationsSettingsView(
                configStore: configStore, permission: NotificationPermission(), requestPermission: {}
            )
            .frame(width: 520),
            appearance: appearance, to: directory, name: "settings-notifications-\(suffix)")
        render(
            RepositoriesSettingsView(
                selection: SelectionStore(configStore: configStore), known: ["acme/api"], check: { _ in true }
            )
            .frame(width: 520, height: 320),
            appearance: appearance, to: directory, name: "settings-repositories-\(suffix)")
        render(
            GeneralSettingsView(configStore: configStore).frame(width: 520),
            appearance: appearance, to: directory, name: "settings-general-\(suffix)")
    }

    private struct Scenario {
        var name: String
        var account: AccountState
        var problem: PollProblem?
        var cache: SnapshotCache?
        var tab: PopoverModel.Section = .reviewRequested
        var triage: Triage = .humans
        var filter = PopoverFilter()
        var board = false
    }

    static func render(_ view: some View, appearance: NSAppearance.Name, to directory: URL, name: String) {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        hosting.appearance = NSAppearance(named: appearance)
        hosting.frame.size = hosting.fittingSize
        hosting.layoutSubtreeIfNeeded()
        // A second pass: the popover sizes its list from a measured height, set after the first layout.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.frame.size = hosting.fittingSize
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(name).png"))
    }
}

/// Synthetic pull requests for snapshots: `acme/api`, `ana`, `bruno`, `carla`, `dave`, `you`.
@MainActor
enum SampleData {
    static let now = Date()

    static func url(_ path: String) -> URL { URL(string: "https://github.com/\(path)") ?? URL(fileURLWithPath: "/") }

    /// `ref` is `owner/name#number`, and doubles as the node ID.
    static func pullRequest(
        _ ref: String, _ title: String, author: String, days: Double, _ change: (inout PullRequest) -> Void = { _ in }
    ) -> PullRequest {
        let parts = ref.split(separator: "#")
        let repository = String(parts.first ?? "")
        let number = Int(parts.last ?? "") ?? 0
        var pullRequest = PullRequest(
            id: ref, number: number, title: title, url: url("\(repository)/pull/\(number)"),
            createdAt: now.addingTimeInterval(-days * 86400), updatedAt: now.addingTimeInterval(-3600),
            author: Actor(login: author), repository: repository)
        change(&pullRequest)
        return pullRequest
    }

    static var cache: SnapshotCache {
        let team = Reviewer.team(organization: "acme", slug: "frontend")
        let you = Reviewer.user(login: "you")
        let backend = Label(name: "backend", color: "0e8a16")
        let urgent = Label(name: "urgent", color: "d93f0b")
        let entries = [
            CachedPullRequest(
                pullRequest: pullRequest(
                    "acme/api#482", "Fix login redirect loop after the SSO session expires", author: "ana", days: 4
                ) {
                    $0.reviewRequests = [you]
                    $0.checks = .failure
                    $0.labels = [urgent, backend]
                },
                role: .reviewRequested, request: RequestInfo(requestedAt: ago(days: 4), requestedBy: "ana"),
                activity: [ActivityStamp(login: "ana", at: ago(days: 0.1))]),
            CachedPullRequest(
                pullRequest: pullRequest("acme/api#490", "Rate-limit the export endpoint", author: "bruno", days: 1) {
                    $0.checks = .pending
                    $0.reviewRequests = [you]
                    $0.labels = [backend]
                },
                role: .reviewRequested, request: RequestInfo(requestedAt: ago(days: 0.08), requestedBy: "bruno")),
            CachedPullRequest(
                pullRequest: pullRequest("globex/web#31", "Paginate the audit log", author: "dave", days: 0.5) {
                    $0.reviewRequests = [you]
                },
                role: .reviewRequested, request: RequestInfo(requestedAt: ago(days: 0.4), requestedBy: "dave")),
            CachedPullRequest(
                pullRequest: pullRequest("acme/api#493", "Bump swift-format to 602.0.0", author: "dependabot", days: 1)
                {
                    $0.author = Actor(login: "dependabot", isBot: true)
                    $0.checks = .success
                    $0.reviewRequests = [you]
                    $0.labels = [Label(name: "dependencies", color: "0366d6")]
                },
                role: .reviewRequested, request: RequestInfo(requestedAt: ago(days: 1), requestedBy: "dependabot")),
            CachedPullRequest(
                pullRequest: pullRequest("acme/web#64", "Try a new date picker", author: "carla", days: 21) {
                    $0.reviewRequests = [you]
                },
                role: .reviewRequested, request: RequestInfo(requestedAt: ago(days: 20), requestedBy: "carla")),
            CachedPullRequest(
                pullRequest: pullRequest(
                    "acme/web#88", "Move checkout to the new payments client", author: "carla", days: 12
                ) {
                    $0.reviewDecision = .approved
                    $0.checks = .success
                    $0.reviewRequests = [team]
                },
                role: .reviewRequested,
                request: RequestInfo(requestedAt: ago(days: 9), requestedBy: "carla", team: team),
                activity: [ActivityStamp(login: "carla", at: ago(days: 1))]),
            CachedPullRequest(
                pullRequest: pullRequest("acme/api#470", "Cache the account lookup", author: "you", days: 4) {
                    $0.mergeable = .conflicting
                    $0.isDraft = true
                    $0.reviewRequests = [.user(login: "ana")]
                    $0.latestReviews = [LatestReview(login: "bruno", state: .approved)]
                },
                role: .authored),
            CachedPullRequest(
                pullRequest: pullRequest("acme/web#91", "Drop the legacy feature flags", author: "you", days: 0.2) {
                    $0.reviewDecision = .approved
                    $0.checks = .success
                },
                role: .authored, commenters: ["dave"]),
            CachedPullRequest(
                pullRequest: pullRequest("acme/api#475", "Retry webhooks with backoff", author: "you", days: 9) {
                    $0.reviewDecision = .changesRequested
                    $0.latestReviews = [LatestReview(login: "carla", state: .changesRequested)]
                },
                role: .authored),
            CachedPullRequest(
                pullRequest: pullRequest("acme/infra#12", "Bump the base image", author: "dave", days: 2) {
                    $0.reviewRequests = [.user(login: "carla")]
                },
                role: .involved),
        ]
        return SnapshotCache(fetchedAt: now, viewerLogin: "you", pullRequests: entries)
    }

    static func ago(days: Double) -> Date { now.addingTimeInterval(-days * 86400) }

    static func watch(account: AccountState, problem: PollProblem?, cache: SnapshotCache?, board: Bool = false)
        -> WatchStore
    {
        var config = Config()
        config.mineLayout = board ? .board : .list
        config.mutes["acme/api#490"] = Config.MuteEntry(ref: "acme/api#490", scope: .all, mutedAt: now)
        let store = WatchStore(configStore: ConfigStore(storage: NoStorage(), initial: config))
        store.apply(
            WatchSnapshot(
                cache: cache,
                state: PersistedState(
                    viewerLogin: "you", baselineAt: now, baselineNoticeDismissed: true,
                    seen: [
                        "acme/web#88": ago(days: 2), "globex/web#31": now, "acme/api#470": now, "acme/web#91": now,
                        "acme/web#64": now,
                    ],
                    seenBaselineAt: ago(days: 30)),
                account: account, problem: problem))
        return store
    }

    static var actions: PopoverActions {
        let row = RowActions(
            open: { _ in }, copy: { _ in }, filterRepository: { _ in }, setMute: { _, _ in }, setIgnored: { _, _ in },
            markSeen: { _ in })
        return PopoverActions(
            refresh: {}, openSettings: {}, checkForUpdates: {}, quit: {}, retry: {}, chooseGhLocation: {},
            launchAtLogin: { _ in }, deliverHeld: {},
            dismissBaselineNotice: {}, close: {}, row: row)
    }
}

/// Snapshots never touch the disk.
private struct NoStorage: ConfigStoring {
    func loadConfig() async throws -> Config { Config() }
    func saveConfig(_ config: Config) async throws {}
}
