import Foundation

/// Pure selection and labeling rules for the compact overview columns.
public enum CompactColumns {
    private static let vendorNames = ["gemini", "claude", "grok", "openai"]

    /// Returns the most constrained specialized-model quota for column 3.
    public static func specialQuota(in snapshot: UsageSnapshot, providerId: String) -> UsageQuota? {
        guard providerId != "grok" else { return nil }
        return snapshot.modelSpecificQuotas.min {
            $0.percentRemaining < $1.percentRemaining
        }
    }

    /// Returns the compact uppercase label for a specialized-model quota.
    public static func label(for quota: UsageQuota) -> String {
        let title = quota.compactTitle ?? quota.quotaType.displayName
        var words = title.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if words.count >= 2, let first = words.first,
           vendorNames.contains(first.lowercased()) {
            words.removeFirst()
        }
        return words.joined(separator: " ").uppercased()
    }
}
