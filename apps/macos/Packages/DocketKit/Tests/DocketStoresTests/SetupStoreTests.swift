import DocketCore
import DocketPersistence
import DocketStores
import DocketUpdate
import Foundation
import Synchronization
import Testing

/// An installer answering from a script; the download itself is covered in `DocketUpdateTests`.
final class ScriptedGhInstaller: GhInstalling {
    private let error: GhInstallError?
    private let count = Mutex(0)

    init(error: GhInstallError? = nil) { self.error = error }

    var installs: Int { count.withLock { $0 } }

    func install() async throws -> URL {
        count.withLock { $0 += 1 }
        if let error { throw error }
        return URL(fileURLWithPath: "/Users/you/Library/Application Support/Docket/bin/gh")
    }
}

@MainActor
final class SetupHarness {
    let watch: WatchStore
    var rechecks = 0
    var scripts: [String] = []
    /// What the next re-check finds.
    var nextAccount: AccountState?

    init(_ account: AccountState) {
        let files = FileStores(
            paths: AppPaths(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)))
        watch = WatchStore(configStore: ConfigStore(storage: files))
        watch.apply(WatchSnapshot(account: account))
    }

    func store(_ installer: ScriptedGhInstaller = ScriptedGhInstaller(), gh: String? = "/opt/homebrew/bin/gh")
        -> SetupStore
    {
        SetupStore(
            watch: watch, installer: installer, locate: { gh },
            recheck: { [self] in
                rechecks += 1
                if let nextAccount { watch.apply(WatchSnapshot(account: nextAccount)) }
            },
            runInTerminal: { [self] in scripts.append($0) })
    }
}

@MainActor
struct SetupStoreTests {
    @Test(arguments: [
        (AccountState.ghNotFound, [SetupStore.StepState.current, .upcoming, .upcoming]),
        (.signedOut, [.done, .current, .upcoming]),
        (.missingScopes(["read:org"]), [.done, .done, .current]),
        (.ready, [.done, .done, .done]),
        (.loading, [.upcoming, .upcoming, .upcoming]),
    ])
    func eachAccountStateIsOneStep(account: AccountState, states: [SetupStore.StepState]) {
        let store = SetupHarness(account).store()
        #expect(SetupStore.Step.allCases.map(store.state) == states)
        #expect(store.isComplete == (account == .ready))
    }

    @Test func installingChecksAgainSoTheNextStepIsCurrent() async {
        let harness = SetupHarness(.ghNotFound)
        harness.nextAccount = .signedOut
        let installer = ScriptedGhInstaller()
        let store = harness.store(installer)
        await store.install()
        #expect(installer.installs == 1)
        #expect(store.activity == .idle)
        #expect(harness.rechecks == 1)
        #expect(store.state(of: .signIn) == .current)
    }

    @Test func aFailedInstallSaysWhyAndCanBeTriedAgain() async {
        let harness = SetupHarness(.ghNotFound)
        let installer = ScriptedGhInstaller(error: .checksumMismatch)
        let store = harness.store(installer)
        await store.install()
        #expect(store.activity == .failed(.checksumMismatch))
        #expect(harness.rechecks == 0)
        await store.install()
        #expect(installer.installs == 2)
    }

    @Test func signingInRunsTheGhInUseInTheTerminal() async throws {
        let harness = SetupHarness(.signedOut)
        let store = harness.store(gh: "/Users/you/Library/Application Support/Docket/bin/gh")
        await store.signIn()
        let script = try #require(harness.scripts.first)
        #expect(script.hasPrefix("#!/bin/zsh\n"))
        #expect(
            script.contains(
                "'/Users/you/Library/Application Support/Docket/bin/gh' 'auth' 'login' '--hostname' 'github.com'"))
        #expect(script.contains("'--web'"))
    }

    @Test func grantingAsksForExactlyTheMissingScopes() async throws {
        let harness = SetupHarness(.missingScopes(["repo", "read:org"]))
        await harness.store().grantScopes()
        let script = try #require(harness.scripts.first)
        #expect(script.contains("'auth' 'refresh' '--hostname' 'github.com' '--scopes' 'repo,read:org'"))
    }

    @Test func withoutAGhNothingRunsInTheTerminal() async {
        let harness = SetupHarness(.signedOut)
        await harness.store(gh: nil).signIn()
        #expect(harness.scripts.isEmpty)
    }

    @Test func keepsCheckingUntilEveryStepIsDone() async {
        let harness = SetupHarness(.signedOut)
        let store = harness.store()
        let checking = Task { await store.keepChecking(every: .milliseconds(5)) }
        try? await Task.sleep(for: .milliseconds(40))
        #expect(harness.rechecks >= 2)
        harness.nextAccount = .ready
        await checking.value
        #expect(store.isComplete)
    }
}
