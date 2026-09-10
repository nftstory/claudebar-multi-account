import Foundation
import Testing
@testable import Domain

@Suite
struct CompactColumnsTests {
    @Test
    func `Claude snapshot selects Fable`() throws {
        let fable = quota(25, type: .modelSpecific("fable"), providerId: "claude")
        let snapshot = makeSnapshot(providerId: "claude", quotas: [
            quota(80, type: .session, providerId: "claude"),
            quota(70, type: .weekly, providerId: "claude"),
            fable,
        ])

        let selected = try #require(CompactColumns.specialQuota(in: snapshot, providerId: "claude"))
        #expect(selected == fable)
        #expect(CompactColumns.label(for: selected) == "FABLE")
    }

    @Test
    func `Antigravity selects lower Pro quota and removes Gemini prefix`() throws {
        let flash = quota(
            90,
            type: .modelSpecific("flash"),
            providerId: "antigravity",
            compactTitle: "Gemini 3.6 Flash"
        )
        let pro = quota(
            40,
            type: .modelSpecific("pro"),
            providerId: "antigravity",
            compactTitle: "Gemini 3.6 Pro"
        )
        let snapshot = makeSnapshot(providerId: "antigravity", quotas: [flash, pro])

        let selected = try #require(CompactColumns.specialQuota(in: snapshot, providerId: "antigravity"))
        #expect(selected == pro)
        #expect(CompactColumns.label(for: selected) == "3.6 PRO")
    }

    @Test
    func `Grok model-specific Build quota is excluded`() {
        let snapshot = makeSnapshot(providerId: "grok", quotas: [
            quota(10, type: .modelSpecific("Build"), providerId: "grok"),
        ])

        #expect(CompactColumns.specialQuota(in: snapshot, providerId: "grok") == nil)
    }

    @Test
    func `time-limit-only snapshot has no specialized-model quota`() {
        let snapshot = makeSnapshot(providerId: "claude", quotas: [
            quota(10, type: .timeLimit("MCP"), providerId: "claude"),
        ])

        #expect(CompactColumns.specialQuota(in: snapshot, providerId: "claude") == nil)
    }

    private func makeSnapshot(providerId: String, quotas: [UsageQuota]) -> UsageSnapshot {
        UsageSnapshot(providerId: providerId, quotas: quotas, capturedAt: Date())
    }

    private func quota(
        _ percentRemaining: Double,
        type: QuotaType,
        providerId: String,
        compactTitle: String? = nil
    ) -> UsageQuota {
        UsageQuota(
            percentRemaining: percentRemaining,
            quotaType: type,
            providerId: providerId,
            compactTitle: compactTitle
        )
    }

    @Test
    func `label drops parenthetical suffixes and vendor word`() {
        let opus = quota(100, type: .modelSpecific("Claude Opus 4.6 (Thinking)"), providerId: "antigravity")
        #expect(CompactColumns.label(for: opus) == "OPUS 4.6")
        #expect(CompactColumns.resetKey(for: opus) == "opus")
        let pro = quota(40, type: .modelSpecific("Gemini 3.6 Pro (Preview)"), providerId: "antigravity")
        #expect(CompactColumns.label(for: pro) == "3.6 PRO")
        #expect(CompactColumns.resetKey(for: pro) == "3.6 pro")
    }
}
