import DocketCore
import DocketUpdate
import Foundation
import Observation

/// The setup window (FR-15): install the GitHub CLI, sign in to it, grant the scopes Docket reads with. Each
/// step is read from the account state the last poll found, so a step done outside Docket is seen too.
@MainActor
@Observable
public final class SetupStore {
    public enum Step: Int, CaseIterable, Sendable {
        case install
        case signIn
        case scopes
    }

    public enum StepState: Equatable, Sendable {
        case done
        case current
        case upcoming
    }

    public enum Activity: Equatable, Sendable {
        case idle
        case installing
        case failed(GhInstallError)
    }

    public private(set) var activity: Activity = .idle

    @ObservationIgnored private let watch: WatchStore
    @ObservationIgnored private let installer: any GhInstalling
    @ObservationIgnored private let locate: @Sendable () async -> String?
    @ObservationIgnored private let recheck: @MainActor () async -> Void
    @ObservationIgnored private let runInTerminal: @MainActor (String) -> Void

    /// - Parameters:
    ///   - locate: The `gh` in use, as the token provider resolves it.
    ///   - recheck: Forgets the `gh` lookup and polls, as `Try Again` does.
    ///   - runInTerminal: Opens a `zsh` script in the user's terminal.
    public init(
        watch: WatchStore, installer: any GhInstalling, locate: @escaping @Sendable () async -> String?,
        recheck: @escaping @MainActor () async -> Void, runInTerminal: @escaping @MainActor (String) -> Void
    ) {
        self.watch = watch
        self.installer = installer
        self.locate = locate
        self.recheck = recheck
        self.runInTerminal = runInTerminal
    }

    public var account: AccountState { watch.account }
    public var isComplete: Bool { account == .ready }

    public var missingScopes: [String] {
        if case .missingScopes(let scopes) = account { return scopes }
        return []
    }

    public func state(of step: Step) -> StepState {
        let current: Int? =
            switch account {
            case .ghNotFound: Step.install.rawValue
            case .signedOut: Step.signIn.rawValue
            case .missingScopes: Step.scopes.rawValue
            case .ready: Step.allCases.count
            case .loading: nil
            }
        guard let current else { return .upcoming }
        if step.rawValue < current { return .done }
        return step.rawValue == current ? .current : .upcoming
    }

    public func install() async {
        guard activity != .installing else { return }
        activity = .installing
        do {
            _ = try await installer.install()
            activity = .idle
            await recheck()
        } catch let error as GhInstallError {
            activity = .failed(error)
        } catch {
            activity = .failed(.unavailable(0))
        }
    }

    public func signIn() async {
        await run(SetupCommand.signIn)
    }

    public func grantScopes() async {
        await run(SetupCommand.grant(missingScopes.isEmpty ? ["repo", "read:org"] : missingScopes))
    }

    /// While the window is open: what the user does in Terminal or the browser shows up within `interval`.
    public func keepChecking(every interval: Duration = .seconds(3)) async {
        while !Task.isCancelled, !isComplete {
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            if activity != .installing { await recheck() }
        }
    }

    private func run(_ arguments: [String]) async {
        guard let gh = await locate() else { return }
        runInTerminal(SetupCommand.script(gh: gh, arguments: arguments))
    }
}
