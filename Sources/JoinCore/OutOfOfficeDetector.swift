import Foundation

/// Calendar backends don't expose Google's "out of office" event type, but Google titles those
/// events predictably in the account's language, so a keyword match on the title works in practice.
public enum OutOfOfficeDetector {
    public static let defaultKeywords: [String] = [
        "out of office", "OOO", "PTO",
        "fuera de la oficina",
        "absent du bureau",
        "abwesend", "außer haus",
        "fora do escritório",
        "fuori sede",
        "afwezig",
    ]

    public static func isOutOfOffice(title: String, keywords: [String]) -> Bool {
        let haystack = title.lowercased()
        for raw in keywords {
            let keyword = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !keyword.isEmpty else { continue }
            if keyword.count <= 4 {
                // Short tokens like "OOO" or "PTO" must stand alone: "Photo review" is not PTO.
                let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: keyword) + "(?![\\p{L}\\p{N}])"
                if haystack.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil { return true }
            } else if haystack.contains(keyword) {
                return true
            }
        }
        return false
    }

    public static func parseKeywords(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
