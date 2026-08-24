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
}
