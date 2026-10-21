import Foundation

public struct CommandResult: Hashable, Sendable {
    public var status: Int32
    public var output: String

    public init(status: Int32, output: String) {
        self.status = status
        self.output = output
    }
}

public enum CommandError: Error, Hashable, Sendable {
    case notExecutable
    case timedOut
}

/// Runs a child process. The token is never in its environment or arguments (`docs/04-data.md` §6).
public protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String], environment: [String: String], timeout: TimeInterval)
        async throws -> CommandResult
    func isExecutable(_ path: String) -> Bool
}

public struct ProcessCommandRunner: CommandRunner {
    public init() {}

    public func isExecutable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    public func run(
        _ executable: String, _ arguments: [String], environment: [String: String], timeout: TimeInterval
    ) async throws -> CommandResult {
        guard isExecutable(executable) else { throw CommandError.notExecutable }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let killer = Task {
            try await Task.sleep(for: .seconds(timeout))
            if process.isRunning { process.terminate() }
        }
        defer { killer.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if finished.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: CommandError.timedOut)
                } else {
                    continuation.resume(
                        returning: CommandResult(
                            status: finished.terminationStatus, output: String(bytes: data, encoding: .utf8) ?? ""))
                }
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: CommandError.notExecutable)
            }
        }
    }
}
