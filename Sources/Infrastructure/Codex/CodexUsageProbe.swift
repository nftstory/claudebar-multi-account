import Foundation
import Domain
import Mockable

// MARK: - Codex Service Protocol

/// Protocol for Codex service - from user's mental model: "Is it available?" and "Get my stats"
@Mockable
public protocol CodexRPCClient: Sendable {
    /// Is the Codex CLI available on this system?
    func isAvailable() -> Bool
    /// Fetch rate limits from Codex service
    func fetchRateLimits() async throws -> CodexRateLimitsResponse
    /// Cleanup resources
    func shutdown()
}

/// Response from Codex rate limits API.
public struct CodexRateLimitsResponse: Sendable, Equatable {
    public let primary: CodexRateLimitWindow?
    public let secondary: CodexRateLimitWindow?
    public let planType: String?

    public init(primary: CodexRateLimitWindow?, secondary: CodexRateLimitWindow?, planType: String? = nil) {
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
    }
}

/// A rate limit window from Codex API.
public struct CodexRateLimitWindow: Sendable, Equatable {
    public let usedPercent: Double
    public let resetDescription: String?
    public let windowDuration: TimeInterval?
    public let resetsAt: Date?

    public init(usedPercent: Double, resetDescription: String?) {
        self.usedPercent = usedPercent
        self.resetDescription = resetDescription
        self.windowDuration = nil
        self.resetsAt = nil
    }

    public init(
        usedPercent: Double,
        resetDescription: String?,
        windowDuration: TimeInterval?,
        resetsAt: Date?
    ) {
        self.usedPercent = usedPercent
        self.resetDescription = resetDescription
        self.windowDuration = windowDuration
        self.resetsAt = resetsAt
    }
}

/// Infrastructure adapter that probes the Codex CLI to fetch usage quotas.
public struct CodexUsageProbe: UsageProbe {
    private let client: CodexRPCClient
    private let providerId: String

    public init(client: CodexRPCClient? = nil, providerId: String = "codex") {
        self.client = client ?? DefaultCodexRPCClient()
        self.providerId = providerId
    }

    /// Probes a second Codex login: the spawned `codex app-server` runs with `CODEX_HOME=<codexHome>`
    /// so the CLI owns that account's credentials and token refresh.
    public init(codexHome: String, providerId: String) {
        let expanded = (codexHome as NSString).expandingTildeInPath
        self.client = DefaultCodexRPCClient(environmentOverrides: ["CODEX_HOME": expanded])
        self.providerId = providerId
    }

    public func isAvailable() async -> Bool {
        client.isAvailable()
    }

    public func probe() async throws -> UsageSnapshot {
        AppLog.probes.info("Starting Codex probe (\(providerId))...")
        defer { client.shutdown() }

        let limits = try await client.fetchRateLimits()
        let snapshot = try Self.mapRateLimitsToSnapshot(limits, providerId: providerId)

        AppLog.probes.info("Codex probe success: \(snapshot.quotas.count) quotas found")
        for quota in snapshot.quotas {
            AppLog.probes.info("  - \(quota.quotaType.displayName): \(Int(quota.percentRemaining))% remaining")
        }
        return snapshot
    }

    /// Maps RPC rate limits response to a UsageSnapshot (internal for testing).
    internal static func mapRateLimitsToSnapshot(
        _ limits: CodexRateLimitsResponse,
        providerId: String = "codex"
    ) throws -> UsageSnapshot {
        var quotas: [UsageQuota] = []
        var firstClassification: QuotaType?
        let now = Date()

        for window in [limits.primary, limits.secondary].compactMap({ $0 }) {
            let classification = quotaType(for: window, now: now)
            let emittedType: QuotaType = classification == firstClassification
                ? .timeLimit("Secondary")
                : classification
            quotas.append(UsageQuota(
                percentRemaining: max(0, 100 - window.usedPercent),
                quotaType: emittedType,
                providerId: providerId,
                resetsAt: window.resetsAt,
                resetText: window.resetDescription,
                windowDuration: window.windowDuration
            ))
            if firstClassification == nil {
                firstClassification = classification
            }
        }

        guard !quotas.isEmpty else {
            AppLog.probes.error("Codex probe failed: no rate limits in RPC response")
            throw ProbeError.parseFailed("No rate limits found")
        }

        return UsageSnapshot(
            providerId: providerId,
            quotas: quotas,
            capturedAt: now
        )
    }

    private static func quotaType(for window: CodexRateLimitWindow, now: Date) -> QuotaType {
        if let duration = window.windowDuration {
            return duration >= 24 * 60 * 60 ? .weekly : .session
        }
        if let resetsAt = window.resetsAt,
           resetsAt.timeIntervalSince(now) > 24 * 60 * 60 {
            return .weekly
        }
        return .session
    }

}
