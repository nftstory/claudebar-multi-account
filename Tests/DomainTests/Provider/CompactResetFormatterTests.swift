import Foundation
import Testing
@testable import Domain

@Suite
struct CompactResetFormatterTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test
    func `formats a reset under one minute away`() {
        let resetDate = now.addingTimeInterval(42)

        #expect(CompactResetFormatter.string(until: resetDate, now: now) == "<1m")
    }

    @Test
    func `formats a reset in minutes`() {
        let resetDate = now.addingTimeInterval(42 * 60)

        #expect(CompactResetFormatter.string(until: resetDate, now: now) == "42m")
    }

    @Test
    func `formats a reset in hours and minutes`() {
        let resetDate = now.addingTimeInterval(2 * 60 * 60 + 8 * 60)

        #expect(CompactResetFormatter.string(until: resetDate, now: now) == "2h 8m")
    }

    @Test
    func `formats a reset in one day and hours`() {
        let resetDate = now.addingTimeInterval(24 * 60 * 60 + 4 * 60 * 60)

        #expect(CompactResetFormatter.string(until: resetDate, now: now) == "1d 4h")
    }

    @Test
    func `formats a reset in several days and hours`() {
        let resetDate = now.addingTimeInterval(6 * 24 * 60 * 60 + 23 * 60 * 60)

        #expect(CompactResetFormatter.string(until: resetDate, now: now) == "6d 23h")
    }

    @Test
    func `reset lines order session weekly then model quotas`() {
        let snapshot = UsageSnapshot(providerId: "claude", quotas: [
            quota(type: .modelSpecific("fable"), resetsAt: now.addingTimeInterval(3 * 24 * 60 * 60)),
            quota(type: .weekly, resetText: "Resets in 1d 4h"),
            quota(type: .session, resetsAt: now.addingTimeInterval(2 * 60 * 60 + 8 * 60)),
        ], capturedAt: now)

        #expect(CompactResetFormatter.lines(for: snapshot, now: now) == [
            "5h 2h 8m",
            "wk 1d 4h",
            "fable 3d",
        ])
    }

    @Test
    func `model reset key uses lowercased compact label capped at six characters`() {
        let snapshot = UsageSnapshot(providerId: "antigravity", quotas: [
            quota(
                type: .modelSpecific("pro"),
                resetsAt: now.addingTimeInterval(4 * 60 * 60),
                compactTitle: "Gemini 3.6 Pro"
            ),
        ], capturedAt: now)

        #expect(CompactResetFormatter.lines(for: snapshot, now: now) == ["3.6 pr 4h"])
    }

    @Test
    func `reset lines do not deduplicate matching deadlines`() {
        let sharedReset = now.addingTimeInterval(24 * 60 * 60)
        let snapshot = UsageSnapshot(providerId: "claude", quotas: [
            quota(type: .weekly, resetsAt: sharedReset),
            quota(type: .modelSpecific("fable"), resetsAt: sharedReset),
        ], capturedAt: now)

        #expect(CompactResetFormatter.lines(for: snapshot, now: now) == [
            "wk 1d",
            "fable 1d",
        ])
    }

    @Test
    func `reset lines use em dash when no quota has a reset`() {
        let snapshot = UsageSnapshot(providerId: "claude", quotas: [
            quota(type: .session),
            quota(type: .weekly),
        ], capturedAt: now)

        #expect(CompactResetFormatter.lines(for: snapshot, now: now) == ["—"])
    }

    private func quota(
        type: QuotaType,
        resetsAt: Date? = nil,
        resetText: String? = nil,
        compactTitle: String? = nil
    ) -> UsageQuota {
        UsageQuota(
            percentRemaining: 50,
            quotaType: type,
            providerId: "test",
            resetsAt: resetsAt,
            resetText: resetText,
            compactTitle: compactTitle
        )
    }
}
