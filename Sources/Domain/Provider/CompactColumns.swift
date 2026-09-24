import Foundation

/// Pure selection and labeling rules for the compact overview columns.
public enum CompactColumns {
    private static let vendorNames = ["gemini", "claude", "grok", "openai"]

    /// The vendor whose models a provider is primarily used for; breaks ties when several models
    /// are equally constrained (e.g. everything at 100%), so Antigravity shows Gemini, not Claude.
    private static let nativeVendor: [String: String] = ["antigravity": "gemini"]

    /// Returns the most constrained specialized-model quota for column 3.
    /// Ties are broken by the provider's native vendor, then flagship ("Pro") models, then the
    /// newest version, so the column stays stable and meaningful when nothing is constrained.
    public static func specialQuota(in snapshot: UsageSnapshot, providerId: String) -> UsageQuota? {
        guard providerId != "grok" else { return nil }
        let vendor = nativeVendor[providerId]
        return snapshot.modelSpecificQuotas.min { lhs, rhs in
            if lhs.percentRemaining != rhs.percentRemaining {
                return lhs.percentRemaining < rhs.percentRemaining
            }
            return tieRank(lhs, vendor: vendor) < tieRank(rhs, vendor: vendor)
        }
    }

    /// Lower ranks win a tie: native vendor first, "Pro" before others, higher version before lower.
    private static func tieRank(_ quota: UsageQuota, vendor: String?) -> (Int, Int, Double, String) {
        let title = stripParentheticals(quota.compactTitle ?? quota.quotaType.displayName)
        let words = title.split(whereSeparator: { $0.isWhitespace }).map { $0.lowercased() }
        let vendorRank = (vendor != nil && words.first == vendor) ? 0 : 1
        let proRank = words.contains("pro") ? 0 : 1
        let version = words.compactMap(Double.init).first ?? 0
        return (vendorRank, proRank, -version, title.lowercased())
    }

    /// Returns the compact uppercase label for a specialized-model quota.
    public static func label(for quota: UsageQuota) -> String {
        let title = stripParentheticals(quota.compactTitle ?? quota.quotaType.displayName)
        var words = title.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if words.count >= 2, let first = words.first,
           vendorNames.contains(first.lowercased()) {
            words.removeFirst()
        }
        return words.joined(separator: " ").uppercased()
    }

    /// Short lowercase key for the resets column: the label's first word, keeping a following word
    /// when the first is a bare version number ("3.6 pro"). Never cuts a word in half.
    public static func resetKey(for quota: UsageQuota) -> String {
        let words = label(for: quota).lowercased().split(separator: " ").map(String.init)
        guard let first = words.first else { return "" }
        if first.first?.isNumber == true, words.count >= 2 {
            return "\(first) \(words[1])"
        }
        return first
    }

    /// Drops "(…)" suffixes such as "(Thinking)" that only truncate in a compact cell.
    private static func stripParentheticals(_ title: String) -> String {
        var result = ""
        var depth = 0
        for character in title {
            if character == "(" { depth += 1; continue }
            if character == ")" { depth = max(0, depth - 1); continue }
            if depth == 0 { result.append(character) }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
