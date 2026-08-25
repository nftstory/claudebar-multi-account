/// Decides whether the icon-only menu bar item should surface a quota alert.
///
/// Only the provider's core session and weekly windows are actionable here.
/// Model-specific and named time-limit quotas intentionally do not affect the
/// status item tint.
public enum StatusItemTint {
    /// The most severe core-window status that should tint the status item.
    /// Returns `nil` when the icon should use the standard template rendering.
    public static func tintStatus(snapshot: UsageSnapshot?) -> QuotaStatus? {
        guard let snapshot else { return nil }

        return [snapshot.sessionQuota, snapshot.weeklyQuota]
            .compactMap { $0?.status }
            .filter { $0 == .critical || $0 == .depleted }
            .max()
    }

    public static func shouldTint(snapshot: UsageSnapshot?) -> Bool {
        tintStatus(snapshot: snapshot) != nil
    }
}
