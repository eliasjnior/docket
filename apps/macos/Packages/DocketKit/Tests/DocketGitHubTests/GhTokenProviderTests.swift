import DocketCore
import Foundation
import Synchronization
import Testing

@testable import DocketGitHub

/// A `CommandRunner` that answers from a script and records every call.
final class ScriptedRunner: CommandRunner {
    struct Call: Equatable {
        var executable: String
        var arguments: [String]
        var environment: [String: String]
    }

    private let executables: Set<String>
    private let results: [String: Result<CommandResult, CommandError>]
    private let recorded = Mutex<[Call]>([])

    init(executables: Set<String>, results: [String: Result<CommandResult, CommandError>]) {
        self.executables = executables
        self.results = results
    }

    var calls: [Call] { recorded.withLock { $0 } }

    func isExecutable(_ path: String) -> Bool { executables.contains(path) }

    func run(_ executable: String, _ arguments: [String], environment: [String: String], timeout: TimeInterval)
        async throws -> CommandResult
    {
        recorded.withLock { $0.append(Call(executable: executable, arguments: arguments, environment: environment)) }
        let result = results[executable]
        guard let result else { throw CommandError.notExecutable }
        return try result.get()
    }
}

struct GhTokenProviderTests {
    private let token = Result<CommandResult, CommandError>.success(CommandResult(status: 0, output: "gho_synthetic\n"))

    @Test func prefersHomebrewAndPassesOnlyHomeAndPath() async throws {
        let runner = ScriptedRunner(
            executables: ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"], results: ["/opt/homebrew/bin/gh": token])
        let provider = GhTokenProvider(runner: runner, home: "/Users/you")
        #expect(try await provider.token() == "gho_synthetic")
        #expect(try await provider.token() == "gho_synthetic")
        #expect(
            runner.calls == [
                ScriptedRunner.Call(
                    executable: "/opt/homebrew/bin/gh", arguments: ["auth", "token", "--hostname", "github.com"],
                    environment: ["HOME": "/Users/you", "PATH": "/opt/homebrew/bin:/usr/bin:/bin"])
            ])
    }

    @Test func findsTheCopyDocketInstalledButPrefersHomebrew() async throws {
        let managed = "/Users/you/Library/Application Support/Docket/bin/gh"
        let runner = ScriptedRunner(executables: [managed], results: [managed: token])
        let provider = GhTokenProvider(runner: runner, home: "/Users/you")
        #expect(try await provider.token() == "gho_synthetic")
        #expect(runner.calls.map(\.executable) == [managed])
        let both = ScriptedRunner(
            executables: [managed, "/opt/homebrew/bin/gh"], results: ["/opt/homebrew/bin/gh": token])
        #expect(await GhTokenProvider(runner: both, home: "/Users/you").location() == "/opt/homebrew/bin/gh")
    }

    @Test func fallsBackToTheLoginShell() async throws {
        let runner = ScriptedRunner(
            executables: ["/Users/you/.local/bin/gh"],
            results: [
                "/bin/zsh": .success(CommandResult(status: 0, output: "/Users/you/.local/bin/gh\n")),
                "/Users/you/.local/bin/gh": token,
            ])
        let provider = GhTokenProvider(runner: runner, home: "/Users/you")
        #expect(try await provider.token() == "gho_synthetic")
        #expect(runner.calls.first?.arguments == ["-lc", "command -v gh"])
        #expect(await provider.location() == "/Users/you/.local/bin/gh")
    }

    @Test func aConfiguredPathWins() async throws {
        let runner = ScriptedRunner(
            executables: ["/opt/homebrew/bin/gh", "/custom/gh"], results: ["/custom/gh": token])
        let provider = GhTokenProvider(runner: runner, configuredPath: { "/custom/gh" })
        #expect(try await provider.token() == "gho_synthetic")
        let missing = GhTokenProvider(runner: runner, configuredPath: { "/nowhere/gh" })
        await #expect(throws: TokenError.ghNotFound) { try await missing.token() }
    }

    @Test func noGhAnywhereIsNotFound() async throws {
        let runner = ScriptedRunner(
            executables: [], results: ["/bin/zsh": .success(CommandResult(status: 1, output: ""))])
        await #expect(throws: TokenError.ghNotFound) { try await GhTokenProvider(runner: runner).token() }
    }

    @Test(arguments: [CommandResult(status: 1, output: "no oauth token"), CommandResult(status: 0, output: "  \n")])
    func aFailedOrEmptyAnswerIsSignedOut(result: CommandResult) async throws {
        let runner = ScriptedRunner(
            executables: ["/opt/homebrew/bin/gh"], results: ["/opt/homebrew/bin/gh": .success(result)])
        await #expect(throws: TokenError.signedOut) { try await GhTokenProvider(runner: runner).token() }
    }

    @Test func aHungGhTimesOut() async throws {
        let runner = ScriptedRunner(
            executables: ["/opt/homebrew/bin/gh"], results: ["/opt/homebrew/bin/gh": .failure(.timedOut)])
        await #expect(throws: TokenError.timedOut) { try await GhTokenProvider(runner: runner).token() }
    }

    @Test func refreshReadsAgainAndResetForgets() async throws {
        let runner = ScriptedRunner(executables: ["/opt/homebrew/bin/gh"], results: ["/opt/homebrew/bin/gh": token])
        let provider = GhTokenProvider(runner: runner)
        _ = try await provider.token()
        _ = try await provider.refresh()
        await provider.reset()
        _ = try await provider.token()
        #expect(runner.calls.count == 3)
    }

    @Test func theRealRunnerRunsAProcessAndTimesOut() async throws {
        let runner = ProcessCommandRunner()
        let echo = try await runner.run("/bin/echo", ["hello"], environment: [:], timeout: 5)
        #expect(echo == CommandResult(status: 0, output: "hello\n"))
        await #expect(throws: CommandError.timedOut) {
            try await runner.run("/bin/sleep", ["5"], environment: [:], timeout: 0.2)
        }
        await #expect(throws: CommandError.notExecutable) {
            try await runner.run("/nowhere", [], environment: [:], timeout: 1)
        }
    }
}
