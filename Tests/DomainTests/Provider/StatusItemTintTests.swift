import Foundation
import Testing
@testable import Domain

@Suite
struct StatusItemTintTests {
    @Test
    func `depleted Fable does not tint when core windows are healthy`() {
        let snapshot = makeSnapshot(
            session: 80,
            weekly: 70,
            extraQuotas: [quota(0, type: .modelSpecific("fable"))]
        )

        #expect(StatusItemTint.shouldTint(snapshot: snapshot) == false)
        #expect(StatusItemTint.tintStatus(snapshot: snapshot) == nil)
    }

    @Test
    func `critical session tints`() {
        let snapshot = makeSnapshot(session: 10, weekly: 70)

        #expect(StatusItemTint.shouldTint(snapshot: snapshot))
        #expect(StatusItemTint.tintStatus(snapshot: snapshot) == .critical)
    }

    @Test
    func `depleted weekly window tints`() {
        let snapshot = makeSnapshot(session: 80, weekly: 0)

        #expect(StatusItemTint.shouldTint(snapshot: snapshot))
        #expect(StatusItemTint.tintStatus(snapshot: snapshot) == .depleted)
    }

    @Test
    func `missing snapshot does not tint`() {
        #expect(StatusItemTint.shouldTint(snapshot: nil) == false)
        #expect(StatusItemTint.tintStatus(snapshot: nil) == nil)
    }

    private func makeSnapshot(
        session: Double? = nil,
        weekly: Double? = nil,
        extraQuotas: [UsageQuota] = []
    ) -> UsageSnapshot {
        var quotas = extraQuotas
        if let session { quotas.append(quota(session, type: .session)) }
        if let weekly { quotas.append(quota(weekly, type: .weekly)) }
        return UsageSnapshot(providerId: "claude", quotas: quotas, capturedAt: Date())
    }

    private func quota(_ percentRemaining: Double, type: QuotaType) -> UsageQuota {
        UsageQuota(percentRemaining: percentRemaining, quotaType: type, providerId: "claude")
    }
}
