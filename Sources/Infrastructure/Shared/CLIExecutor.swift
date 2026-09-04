import Foundation
import Mockable

/// Result of executing a CLI command.
public struct CLIResult: Sendable, Equatable {
    public let output: String
    public let exitCode: Int32

    public init(output: String, exitCode: Int32 = 0) {
        self.output = output
        self.exitCode = exitCode
    }
}

/// Determines when an interactive CLI capture is complete.
public enum CompletionPolicy: Sendable, Equatable {
    /// Complete after the existing three-second meaningful-output idle window.
    case idle
    /// Complete only when the rendered terminal screen is ready and no longer pending.
    case renderedScreen(pending: [String], ready: [String])
}

/// Protocol for executing CLI commands.
/// From user's mental model: "Is this tool available?" and "Run it and get my stats"
@Mockable
public protocol CLIExecutor: Sendable {
    /// Finds a tool on the system. Returns the path if found, nil otherwise.
    func locate(_ binary: String) -> String?

    /// Runs a CLI command and returns the result.
    ///
    /// - Parameters:
    ///   - binary: The CLI tool to run
    ///   - args: Command-line arguments
    ///   - input: Text to send to the command
    ///   - timeout: Maximum time to wait
    ///   - workingDirectory: Directory to run in (nil = inherited)
    ///   - autoResponses: Automatic responses to prompts (prompt text → response to send)
    ///   - completion: Policy used to decide when interactive output is complete
    func execute(
        binary: String,
        args: [String],
        input: String?,
        timeout: TimeInterval,
        workingDirectory: URL?,
        autoResponses: [String: String],
        completion: CompletionPolicy
    ) throws -> CLIResult
}

public extension CLIExecutor {
    func execute(
        binary: String,
        args: [String],
        input: String?,
        timeout: TimeInterval,
        workingDirectory: URL?,
        autoResponses: [String: String],
        completion: CompletionPolicy = .idle
    ) throws -> CLIResult {
        try execute(
            binary: binary,
            args: args,
            input: input,
            timeout: timeout,
            workingDirectory: workingDirectory,
            autoResponses: autoResponses,
            completion: completion
        )
    }
}
