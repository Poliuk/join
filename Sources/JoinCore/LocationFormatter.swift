import Foundation

/// Turns an event's free-text location into something short enough for a list row, and decides
/// whether it is a place you travel to (so the menu bar panel can offer directions).
public enum LocationFormatter {
    /// Words that mean the "location" is a video service or a call, not a place on a map.
    static let virtualPlaceKeywords: [String] = [
        "zoom", "google meet", "hangouts", "microsoft teams", "teams meeting", "webex", "skype",
        "facetime", "whereby", "jitsi", "slack huddle", "online", "virtual", "video call", "phone call",
    ]

    /// "C. de Ruiz de Alarcón, 23, Retiro, 28014 Madrid, España" → "C. de Ruiz de Alarcón, 23 · Retiro".
    /// A "Place name\nStreet, City, …" location (the shape Calendar uses for places picked from Maps)
    /// becomes "Place name · City".
    public static func shortLocation(_ location: String) -> String {
        let lines = location
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return location.trimmingCharacters(in: .whitespacesAndNewlines) }

        if lines.count > 1 {
            let address = components(of: lines.dropFirst().joined(separator: ", "))
            if let locality = locality(in: address, from: streetLength(of: address)) {
                return "\(first) · \(locality)"
            }
            return first
        }

        let parts = components(of: first)
        guard parts.count > 1 else { return first }
        let length = streetLength(of: parts)
        let street = parts.prefix(length).joined(separator: ", ")
        if let locality = locality(in: parts, from: length) {
            return "\(street) · \(locality)"
        }
        return street
    }

    /// True for a location that names a place, false for links and video services.
    public static func isPhysicalPlace(_ location: String?) -> Bool {
        guard let text = location?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return false }
        let lowered = text.lowercased()
        if lowered.contains("://") || lowered.hasPrefix("www.") { return false }
        for keyword in virtualPlaceKeywords {
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: keyword) + "(?![\\p{L}\\p{N}])"
            if lowered.range(of: pattern, options: .regularExpression) != nil { return false }
        }
        return true
    }

    /// A meeting you go to rather than join: it has a place and no join link.
    public static func isInPerson(_ meeting: Meeting) -> Bool {
        meeting.joinURL == nil && isPhysicalPlace(meeting.location)
    }

    /// Apple Maps directions from the current location to `location`.
    public static func directionsURL(to location: String) -> URL? {
        let destination = location
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        guard !destination.isEmpty else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = destination.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://maps.apple.com/?daddr=\(encoded)")
    }

    private static func components(of text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The street plus its house number when the number is a component of its own ("C. de Ruiz de Alarcón, 23").
    private static func streetLength(of parts: [String]) -> Int {
        parts.count > 1 && isHouseNumber(parts[1]) ? 2 : 1
    }

    private static func isHouseNumber(_ text: String) -> Bool {
        if text.lowercased() == "s/n" { return true }
        return text.range(of: #"^\d{1,4}\s?\p{L}{0,3}(?:\s?[-/]\s?\d{1,4}\s?\p{L}{0,3})?$"#, options: .regularExpression) != nil
    }

    /// The first component after the street, with postal codes removed ("28014 Madrid" → "Madrid").
    private static func locality(in parts: [String], from index: Int) -> String? {
        guard index < parts.count else { return nil }
        for part in parts[index...] {
            let words = part.split(separator: " ").filter { word in !word.contains(where: \.isNumber) }
            let cleaned = words.joined(separator: " ")
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }
}
