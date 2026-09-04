import Foundation
import Domain

/// Default implementation of CodexRPCClient that communicates with `codex app-server`.
/// Uses RPCTransport for communication, enabling testability.
public final class DefaultCodexRPCClient: CodexRPCClient, @unchecked Sendable {
    private let executable: String
    private let cliExecutor: CLIExecutor
    private let transport: RPCTransport?
    private var nextID = 1
    private var didLogWindowKeys = false

    /// Package-internal: allows tests to inject a mock transport for the production (no-injection) code path.
    var transportFactory: ((String, [String]) throws -> RPCTransport)?

    /// Default initializer - uses real CLI executor and creates transport lazily.
    public init(executable: String = "codex", cliExecutor: CLIExecutor? = nil) {
        self.executable = executable
        self.cliExecutor = cliExecutor ?? DefaultCLIExecutor()
        self.transport = nil
    }

    /// Internal initializer for testing with mock transport.
    init(transport: RPCTransport, cliExecutor: CLIExecutor? = nil) {
        self.executable = "codex"
        self.cliExecutor = cliExecutor ?? DefaultCLIExecutor()
        self.transport = transport
    }

    public func isAvailable() -> Bool {
        let binaryName = executable
        if cliExecutor.locate(binaryName) != nil {
            return true
        }
        
        // Log diagnostic info when binary not found
        let env = ProcessInfo.processInfo.environment
        AppLog.probes.error("Codex binary '\(binaryName)' not found in PATH")
        AppLog.probes.info("Current directory: \(FileManager.default.currentDirectoryPath)")
        AppLog.probes.info("PATH: \(env["PATH"] ?? "<not set>")")
        return false
    }

    public func fetchRateLimits() async throws -> CodexRateLimitsResponse {
        do {
            return try await fetchViaRPC()
        } catch {
            let message = "Codex app-server failed: \(error.localizedDescription)"
            AppLog.probes.error("\(message)")
            throw ProbeError.executionFailed(message)
        }
    }

    // MARK: - RPC Approach

    private func fetchViaRPC() async throws -> CodexRateLimitsResponse {
        let activeTransport: RPCTransport
        let ownsTransport: Bool
        if let transport = self.transport {
            activeTransport = transport
            ownsTransport = false
        } else {
            let factory = transportFactory ?? { exec, args in
                try ProcessRPCTransport(executable: exec, arguments: args)
            }
            activeTransport = try factory(executable, ["-s", "read-only", "-a", "never", "app-server"])
            ownsTransport = true
        }
        defer {
            if ownsTransport {
                activeTransport.close()
            }
        }

        // Initialize RPC connection
        _ = try await request(transport: activeTransport, method: "initialize", params: [
            "clientInfo": ["name": "claudebar", "version": "1.0.0"]
        ])
        try sendNotification(transport: activeTransport, method: "initialized")

        // Fetch rate limits
        let message = try await request(transport: activeTransport, method: "account/rateLimits/read")

        // Log raw response
        if let data = try? JSONSerialization.data(withJSONObject: message, options: .prettyPrinted),
           let jsonString = String(data: data, encoding: .utf8) {
            AppLog.probes.debug("Codex RPC raw response:\n\(jsonString)")
        }

        guard let result = message["result"] as? [String: Any] else {
            AppLog.probes.error("No result in response: \(String(describing: message))")
            throw ProbeError.parseFailed("Invalid rate limits response")
        }

        guard let rateLimits = result["rateLimits"] as? [String: Any] else {
            AppLog.probes.error("No rateLimits in result: \(String(describing: result))")
            throw ProbeError.parseFailed("No rateLimits in response")
        }

        let planType = rateLimits["planType"] as? String
        AppLog.probes.info("Codex plan type: \(planType ?? "unknown")")

        let primary = parseWindow(rateLimits["primary"])
        let secondary = parseWindow(rateLimits["secondary"])

        // If plan is free and no limits, create default "unlimited" quotas
        if primary == nil && secondary == nil {
            if planType == "free" {
                AppLog.probes.info("Codex free plan - returning unlimited quotas")
                return CodexRateLimitsResponse(
                    primary: CodexRateLimitWindow(usedPercent: 0, resetDescription: "Free plan"),
                    secondary: nil,
                    planType: planType
                )
            }
            // No rate limit data available yet
            throw ProbeError.parseFailed("No rate limits available yet - make some API calls first")
        }

        return CodexRateLimitsResponse(primary: primary, secondary: secondary, planType: planType)
    }

    // MARK: - Parsing Helpers

    internal func parseWindow(_ value: Any?) -> CodexRateLimitWindow? {
        guard let dict = value as? [String: Any] else {
            AppLog.probes.debug("parseWindow: value is not a dict: \(String(describing: value))")
            return nil
        }

        if !didLogWindowKeys {
            AppLog.probes.debug("parseWindow dict keys: \(dict.keys.sorted().joined(separator: ", "))")
            didLogWindowKeys = true
        }

        guard let usedPercent = number(from: dict["usedPercent"]) else {
            AppLog.probes.debug("parseWindow: no usedPercent in dict")
            return nil
        }

        var resetDescription: String?
        let resetsAt = number(from: dict["resetsAt"])
            .map(Date.init(timeIntervalSince1970:))
        if let resetsAt {
            resetDescription = formatResetTime(resetsAt)
        }

        let windowDuration: TimeInterval?
        if let minutes = number(from: dict["windowDurationMins"]) ?? number(from: dict["windowMinutes"]) {
            windowDuration = minutes * 60
        } else {
            windowDuration = number(from: dict["windowDurationSeconds"])
        }

        return CodexRateLimitWindow(
            usedPercent: usedPercent,
            resetDescription: resetDescription,
            windowDuration: windowDuration,
            resetsAt: resetsAt
        )
    }

    private func number(from value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    internal func formatResetTime(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "Resets soon" }

        let days = Int(interval / 86400)
        let hours = Int((interval.truncatingRemainder(dividingBy: 86400)) / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)

        if days > 0 {
            return "Resets in \(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else {
            return "Resets in \(minutes)m"
        }
    }

    public func shutdown() {
        transport?.close()
    }

    // MARK: - JSON-RPC

    private func request(transport: RPCTransport, method: String, params: [String: Any]? = nil) async throws -> [String: Any] {
        let id = nextID
        nextID += 1

        try sendRequest(transport: transport, id: id, method: method, params: params)

        while true {
            let message = try await readNextMessage(transport: transport)

            // Skip notifications
            if message["id"] == nil {
                continue
            }

            guard let messageID = message["id"] as? Int, messageID == id else {
                continue
            }

            if let error = message["error"] as? [String: Any],
               let errorMessage = error["message"] as? String {
                throw ProbeError.executionFailed("RPC error: \(errorMessage)")
            }

            return message
        }
    }

    private func sendNotification(transport: RPCTransport, method: String) throws {
        let payload: [String: Any] = ["method": method, "params": [:]]
        try sendPayload(transport: transport, payload: payload)
    }

    private func sendRequest(transport: RPCTransport, id: Int, method: String, params: [String: Any]?) throws {
        let payload: [String: Any] = [
            "id": id,
            "method": method,
            "params": params ?? [:]
        ]
        try sendPayload(transport: transport, payload: payload)
    }

    private func sendPayload(transport: RPCTransport, payload: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        try transport.send(data)
    }

    private func readNextMessage(transport: RPCTransport) async throws -> [String: Any] {
        while true {
            let data = try await transport.receive()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            return json
        }
    }
}
