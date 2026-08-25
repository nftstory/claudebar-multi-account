import Darwin
import Foundation
import Domain

/// Runs short, non-interactive commands without allocating a PTY.
protocol SimpleCommandRunning: Sendable {
    func run(_ binary: String, _ args: [String], timeout: TimeInterval) throws -> CLIResult
}

/// A small `Process` + `Pipe` runner for commands whose exit status is meaningful.
struct SimpleCommandRunner: SimpleCommandRunning {
    func run(_ binary: String, _ args: [String], timeout: TimeInterval) throws -> CLIResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args

        let stdout = Pipe()
        let output = OutputBuffer()
        let handle = stdout.fileHandleForReading
        handle.readabilityHandler = { fileHandle in
            output.append(fileHandle.availableData)
        }
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
        } catch {
            handle.readabilityHandler = nil
            throw ProbeError.executionFailed("Failed to run \(binary): \(error.localizedDescription)")
        }

        if completion.wait(timeout: .now() + timeout) == .timedOut {
            if process.isRunning {
                process.terminate()
            }
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
            completion.wait()
            process.waitUntilExit()
            handle.readabilityHandler = nil
            throw ProbeError.timeout
        }

        process.waitUntilExit()
        handle.readabilityHandler = nil
        output.append(handle.readDataToEndOfFile())

        return CLIResult(
            output: String(data: output.data, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }
}

/// Preserves the existing test seam for callers that inject a `CLIExecutor`.
struct CLIExecutorCommandRunner: SimpleCommandRunning {
    let executor: any CLIExecutor

    func run(_ binary: String, _ args: [String], timeout: TimeInterval) throws -> CLIResult {
        try executor.execute(
            binary: binary,
            args: args,
            input: nil,
            timeout: timeout,
            workingDirectory: nil,
            autoResponses: [:]
        )
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
