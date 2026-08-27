import Foundation

/// Formats a reset deadline for the compact overview cell.
public enum CompactResetFormatter {
    /// Returns a prefix-free countdown with no more than two non-zero units.
    public static func string(until resetDate: Date, now: Date) -> String {
        let totalSeconds = max(0, Int(resetDate.timeIntervalSince(now)))
        guard totalSeconds >= 60 else { return "<1m" }

        let totalMinutes = totalSeconds / 60
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        var parts: [String] = []
        if days > 0 { parts.append("\(days)d") }
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 { parts.append("\(minutes)m") }
        return parts.prefix(2).joined(separator: " ")
    }

    /// Builds the reset lines shown at the far right of a compact overview row.
    public static func lines(for snapshot: UsageSnapshot, providerId: String, now: Date) -> [String] {
        let orderedQuotas = [
            snapshot.sessionQuota,
            snapshot.weeklyQuota,
            CompactColumns.specialQuota(in: snapshot, providerId: providerId),
        ].compactMap { $0 }
        let lines = orderedQuotas.compactMap { quota -> String? in
            guard let countdown = countdown(for: quota, now: now) else { return nil }
            return "\(key(for: quota)) \(countdown)"
        }
        return lines.isEmpty ? ["—"] : lines
    }

    private static func key(for quota: UsageQuota) -> String {
        switch quota.quotaType {
        case .session:
            return "5h"
        case .weekly:
            return "wk"
        case .modelSpecific:
            return String(CompactColumns.label(for: quota).lowercased().prefix(6))
        case .timeLimit:
            return ""
        }
    }

    private static func countdown(for quota: UsageQuota, now: Date) -> String? {
        if let resetsAt = quota.resetsAt {
            return string(until: resetsAt, now: now)
        }

        guard let resetText = quota.resetText else { return nil }
        for prefix in ["Resets in ", "Resets "] {
            if let range = resetText.range(of: prefix, options: [.anchored, .caseInsensitive]) {
                return String(resetText[range.upperBound...])
            }
        }
        return resetText
    }
}
