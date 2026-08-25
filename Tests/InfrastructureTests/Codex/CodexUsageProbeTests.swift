import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite
struct CodexUsageProbeTests {

    @Test
    func `isAvailable returns true when client finds binary`() async {
        // Given
        let mockClient = MockCodexRPCClient()
        given(mockClient).isAvailable().willReturn(true)
        let probe = CodexUsageProbe(client: mockClient)

        // When & Then
        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns false when client cannot find binary`() async {
        // Given
        let mockClient = MockCodexRPCClient()
        given(mockClient).isAvailable().willReturn(false)
        let probe = CodexUsageProbe(client: mockClient)

        // When & Then
        #expect(await probe.isAvailable() == false)
    }

    @Test
    func `stripANSICodes removes colors`() {
        let input = "\u{1B}[32mGreen\u{1B}[0m Text"
        #expect(CodexUsageProbe.stripANSICodes(input) == "Green Text")
    }

    @Test
    func `extractUsageError finds common errors`() {
        #expect(CodexUsageProbe.extractUsageError("data not available yet") != nil)
        #expect(CodexUsageProbe.extractUsageError("Update available: 1.2.1 ... codex") == .updateRequired)
        #expect(CodexUsageProbe.extractUsageError("All good") == nil)
    }
}

// MARK: - Probe Tests

@Suite
struct CodexUsageProbeRPCTests {

    @Test
    func `probe returns snapshot from client`() async throws {
        // Given
        let mockClient = MockCodexRPCClient()
        given(mockClient).fetchRateLimits().willReturn(
            CodexRateLimitsResponse(
                primary: CodexRateLimitWindow(
                    usedPercent: 30,
                    resetDescription: "Resets in 2h",
                    windowDuration: 5 * 60 * 60,
                    resetsAt: Date().addingTimeInterval(2 * 60 * 60)
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 50,
                    resetDescription: "Resets in 3d",
                    windowDuration: 7 * 24 * 60 * 60,
                    resetsAt: Date().addingTimeInterval(3 * 24 * 60 * 60)
                ),
                planType: "pro"
            )
        )
        given(mockClient).shutdown().willReturn(())

        let probe = CodexUsageProbe(client: mockClient)

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.providerId == "codex")
        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.sessionQuota?.percentRemaining == 70) // 100 - 30
        #expect(snapshot.weeklyQuota?.percentRemaining == 50) // 100 - 50
    }

    @Test
    func `probe returns only primary quota when secondary is nil`() async throws {
        // Given
        let mockClient = MockCodexRPCClient()
        given(mockClient).fetchRateLimits().willReturn(
            CodexRateLimitsResponse(
                primary: CodexRateLimitWindow(usedPercent: 25, resetDescription: nil),
                secondary: nil
            )
        )
        given(mockClient).shutdown().willReturn(())

        let probe = CodexUsageProbe(client: mockClient)

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.sessionQuota?.percentRemaining == 75)
        #expect(snapshot.weeklyQuota == nil)
    }

    @Test
    func `probe handles free plan with zero usage`() async throws {
        // Given
        let mockClient = MockCodexRPCClient()
        given(mockClient).fetchRateLimits().willReturn(
            CodexRateLimitsResponse(
                primary: CodexRateLimitWindow(usedPercent: 0, resetDescription: "Free plan"),
                secondary: nil,
                planType: "free"
            )
        )
        given(mockClient).shutdown().willReturn(())

        let probe = CodexUsageProbe(client: mockClient)

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.sessionQuota?.percentRemaining == 100)
    }

    @Test
    func `probe clamps negative percent remaining to zero`() async throws {
        // Given - usage over 100%
        let mockClient = MockCodexRPCClient()
        given(mockClient).fetchRateLimits().willReturn(
            CodexRateLimitsResponse(
                primary: CodexRateLimitWindow(usedPercent: 110, resetDescription: nil),
                secondary: nil
            )
        )
        given(mockClient).shutdown().willReturn(())

        let probe = CodexUsageProbe(client: mockClient)

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.sessionQuota?.percentRemaining == 0) // max(0, 100-110)
    }

    @Test
    func `probe shuts down client after fetch`() async throws {
        // Given
        let mockClient = MockCodexRPCClient()
        given(mockClient).fetchRateLimits().willReturn(
            CodexRateLimitsResponse(
                primary: CodexRateLimitWindow(usedPercent: 50, resetDescription: nil),
                secondary: nil
            )
        )
        given(mockClient).shutdown().willReturn(())

        let probe = CodexUsageProbe(client: mockClient)

        // When
        _ = try await probe.probe()

        // Then - verify shutdown was called
        verify(mockClient).shutdown().called(.atLeastOnce)
    }
}

// MARK: - Mapping Tests

@Suite
struct CodexRateLimitsToSnapshotMappingTests {

    @Test
    func `maps primary window to session quota`() throws {
        let response = CodexRateLimitsResponse(
            primary: CodexRateLimitWindow(
                usedPercent: 40,
                resetDescription: "Resets in 1h",
                windowDuration: 5 * 60 * 60,
                resetsAt: Date().addingTimeInterval(60 * 60)
            ),
            secondary: nil
        )

        let snapshot = try CodexUsageProbe.mapRateLimitsToSnapshot(response)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.sessionQuota?.percentRemaining == 60)
        #expect(snapshot.sessionQuota?.resetText == "Resets in 1h")
    }

    @Test
    func `maps single seven day window to weekly quota`() throws {
        let resetsAt = Date().addingTimeInterval(6 * 24 * 60 * 60)
        let response = CodexRateLimitsResponse(
            primary: CodexRateLimitWindow(
                usedPercent: 20,
                resetDescription: "Resets in 6d",
                windowDuration: 7 * 24 * 60 * 60,
                resetsAt: resetsAt
            ),
            secondary: nil
        )

        let snapshot = try CodexUsageProbe.mapRateLimitsToSnapshot(response)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.weeklyQuota?.percentRemaining == 80)
        #expect(snapshot.weeklyQuota?.resetText == "Resets in 6d")
        #expect(snapshot.weeklyQuota?.windowDuration == TimeInterval(7 * 24 * 60 * 60))
        #expect(snapshot.weeklyQuota?.resetsAt == resetsAt)
        #expect(snapshot.sessionQuota == nil)
    }

    @Test
    func `maps five hour and seven day windows to session and weekly quotas`() throws {
        let response = CodexRateLimitsResponse(
            primary: CodexRateLimitWindow(
                usedPercent: 30,
                resetDescription: nil,
                windowDuration: 5 * 60 * 60,
                resetsAt: nil
            ),
            secondary: CodexRateLimitWindow(
                usedPercent: 60,
                resetDescription: nil,
                windowDuration: 7 * 24 * 60 * 60,
                resetsAt: nil
            )
        )

        let snapshot = try CodexUsageProbe.mapRateLimitsToSnapshot(response)

        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.sessionQuota?.percentRemaining == 70)
        #expect(snapshot.weeklyQuota?.percentRemaining == 40)
    }

    @Test
    func `infers weekly quota when duration missing and reset is six days away`() throws {
        let resetsAt = Date().addingTimeInterval(6 * 24 * 60 * 60)
        let response = CodexRateLimitsResponse(
            primary: CodexRateLimitWindow(
                usedPercent: 35,
                resetDescription: "Resets in 6d",
                windowDuration: nil,
                resetsAt: resetsAt
            ),
            secondary: nil
        )

        let snapshot = try CodexUsageProbe.mapRateLimitsToSnapshot(response)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.weeklyQuota?.percentRemaining == 65)
        #expect(snapshot.weeklyQuota?.resetsAt == resetsAt)
        #expect(snapshot.sessionQuota == nil)
    }

    @Test
    func `maps duplicate classifications to secondary time limit`() throws {
        let response = CodexRateLimitsResponse(
            primary: CodexRateLimitWindow(
                usedPercent: 10,
                resetDescription: nil,
                windowDuration: 5 * 60 * 60,
                resetsAt: nil
            ),
            secondary: CodexRateLimitWindow(
                usedPercent: 20,
                resetDescription: nil,
                windowDuration: 8 * 60 * 60,
                resetsAt: nil
            )
        )

        let snapshot = try CodexUsageProbe.mapRateLimitsToSnapshot(response)

        #expect(snapshot.quotas.map(\.quotaType) == [.session, .timeLimit("Secondary")])
        #expect(snapshot.quotas[1].windowDuration == TimeInterval(8 * 60 * 60))
    }

    @Test
    func `throws when no rate limits found`() throws {
        let response = CodexRateLimitsResponse(primary: nil, secondary: nil)

        #expect(throws: ProbeError.self) {
            try CodexUsageProbe.mapRateLimitsToSnapshot(response)
        }
    }

    @Test
    func `sets provider id to codex`() throws {
        let response = CodexRateLimitsResponse(
            primary: CodexRateLimitWindow(usedPercent: 0, resetDescription: nil),
            secondary: nil
        )

        let snapshot = try CodexUsageProbe.mapRateLimitsToSnapshot(response)

        #expect(snapshot.providerId == "codex")
    }
}
