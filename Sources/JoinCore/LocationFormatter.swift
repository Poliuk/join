import Foundation

/// Turns an event's free-text location into something short enough for a list row, and decides
/// whether it is a place you travel to (so the menu bar panel can offer directions).
public enum LocationFormatter {
    /// Words that mean the "location" is a video service or a call, not a place on a map.
    static let virtualPlaceKeywords: [String] = [
        "zoom", "google meet", "hangouts", "microsoft teams", "teams meeting", "webex", "skype",
        "facetime", "whereby", "jitsi", "slack huddle", "online", "virtual", "video call", "phone call",
    ]

    /// Service names that are only virtual when they are the whole location: "Teams" is a call, "Teams Room 3" a room.
    static let virtualServiceNames: Set<String> = [
        "teams", "ms teams", "meet", "hangout", "chime", "amazon chime", "bluejeans", "blue jeans",
        "gotomeeting", "goto meeting", "ringcentral", "slack", "huddle", "discord", "tuple", "phone", "call", "remote",
    ]

    /// "C. de Ruiz de Alarcón, 23, Retiro, 28014 Madrid, España" → "C. de Ruiz de Alarcón, 23 · Retiro".
    /// A place with an address ("Museo del Prado, C. de Ruiz de Alarcón, 23, Retiro, …", or "Café Comercial"
    /// over "Glorieta de Bilbao, 7, 28004 Madrid, …" as Calendar stores places picked from Maps) becomes
    /// "Place name · District or city".
    public static func shortLocation(_ location: String) -> String {
        let lines = location
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return location.trimmingCharacters(in: .whitespacesAndNewlines) }
        let parts = lines.flatMap(components(of:))
        let usStyle = parts.contains { matches($0, #"\b\p{Lu}{2}\s+\d{5}(?:-\d{4})?$"#) }

        if let street = street(in: parts, usStyle: usStyle) {
            let name = street.lowerBound > 0 ? parts[0] : parts[street].joined(separator: ", ")
            guard let locality = locality(in: parts, from: street.upperBound, usStyle: usStyle) else { return name }
            return "\(name) · \(locality)"
        }

        // No house number anywhere: the first line names the place, and an address line below it starts with a
        // street, unless it holds a postcode ("Plaza Mayor" over "28012 Madrid").
        if lines.count > 1 {
            let address = components(of: lines.dropFirst().joined(separator: ", "))
            let start = address.first?.contains(where: \.isNumber) == true ? 0 : 1
            guard let locality = locality(in: address, from: start, usStyle: usStyle) else { return first }
            return "\(first) · \(locality)"
        }
        guard parts.count > 1, let locality = locality(in: parts, from: 1, usStyle: usStyle) else { return parts.first ?? first }
        return "\(parts[0]) · \(locality)"
    }

    /// The part of `location` that names a place, without the links, phone numbers and video services that
    /// share the field: "Sala Retiro; Microsoft Teams Meeting" → "Sala Retiro". Nil when nothing is left.
    public static func physicalPlace(in location: String?) -> String? {
        guard let text = location?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let segments = text
            .split(whereSeparator: { $0 == ";" || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let places = segments.filter { !isVirtual($0) }
        if places.isEmpty { return nil }
        return places.count == segments.count ? text : places.joined(separator: "\n")
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

    // MARK: Virtual locations

    private static func isVirtual(_ segment: String) -> Bool {
        let lowered = segment.lowercased()
        if lowered.contains("://") || lowered.hasPrefix("www.") || isBareLink(lowered) || isPhoneNumber(lowered) { return true }
        if virtualServiceNames.contains(lowered) { return true }
        return virtualPlaceKeywords.contains { keyword in
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: keyword) + "(?![\\p{L}\\p{N}])"
            return lowered.range(of: pattern, options: .regularExpression) != nil
        }
    }

    /// "meet.google.com/abc-defg-hij", "zoom.us/j/123": a host name, optionally with a path, and nothing else.
    private static func isBareLink(_ text: String) -> Bool {
        matches(text, #"^(?:[a-z0-9-]+\.)+[a-z]{2,}(?:[/?#:]\S*)?$"#)
    }

    /// "Tel: +34 600 123 456", "+1 646-558-8656,,123456789#": at least seven digits and no words besides a label.
    private static func isPhoneNumber(_ text: String) -> Bool {
        if text.hasPrefix("tel:") { return true }
        let number = text.replacingOccurrences(
            of: #"^(?:tel|tlf|phone|telephone|tel[eé]fono|dial[- ]?in|call)\.?\s*:?\s*"#,
            with: "",
            options: .regularExpression
        )
        return matches(number, #"^\+?[\d\s().\-–,#*]+$"#) && number.filter(\.isNumber).count >= 7
    }

    // MARK: Addresses

    private static func components(of text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The components that hold the street and its house number: "C. de Ruiz de Alarcón, 23", "66 Mint St",
    /// "Unter den Linden 77". A number in front or in a component of its own wins over one at the end,
    /// which may belong to a name ("Microsoft Building 92, 15010 NE 36th St, …").
    private static func street(in parts: [String], usStyle: Bool) -> Range<Int>? {
        for index in parts.indices {
            if index + 1 < parts.count, isHouseNumber(parts[index + 1]), !isHouseNumber(parts[index]) {
                return index..<index + 2
            }
            if leadsWithHouseNumber(parts[index], usStyle: usStyle) { return index..<index + 1 }
        }
        return parts.firstIndex(where: endsWithHouseNumber).map { $0..<$0 + 1 }
    }

    /// "1012 LG" in "1012 LG Amsterdam": the letters belong to the postcode, not to the town.
    private static let dutchPostcode = #"^\d{4}\s?\p{Lu}{2}(?=\s|$)"#

    private static func isHouseNumber(_ text: String) -> Bool {
        if text.lowercased() == "s/n" { return true }
        return matches(text, #"^\d{1,4}\s?\p{L}{0,3}(?:\s?[-/]\s?\d{1,4}\s?\p{L}{0,3})?$"#)
    }

    /// A house number followed by at least two words, so "28014 Madrid" or "8001 Zürich" isn't a street.
    /// Five-digit house numbers only count in US-style addresses ("…, WA 98052"), where postcodes come last;
    /// elsewhere "28660 Boadilla del Monte" is a postcode and a town, like the Dutch "1012 LG Amsterdam".
    private static func leadsWithHouseNumber(_ text: String, usStyle: Bool) -> Bool {
        if !usStyle && matches(text, dutchPostcode) { return false }
        let digits = usStyle ? "{1,5}" : "{1,4}"
        return matches(text, #"^\d"# + digits + #"\p{L}?(?:[-/]\d{1,5}\p{L}?)?\s+\S+\s+\S+"#)
    }

    /// "Unter den Linden 77", "Room 4". The word before the number needs a lowercase letter, so a region and
    /// postcode ("Sydney NSW 2000") isn't taken for a street.
    private static func endsWithHouseNumber(_ text: String) -> Bool {
        matches(text, #"\p{Ll}\S*\s+\d{1,4}\p{L}?$"#)
    }

    /// The first component from `index` that names a district or city, with postal codes and a trailing
    /// region code removed ("28014 Madrid" → "Madrid", "Cupertino CA 95014" → "Cupertino").
    private static func locality(in parts: [String], from index: Int, usStyle: Bool) -> String? {
        guard index < parts.count else { return nil }
        for part in parts[index...] where !isHouseNumber(part) && !leadsWithHouseNumber(part, usStyle: usStyle) {
            let place = usStyle ? part : part.replacingOccurrences(of: dutchPostcode, with: "", options: .regularExpression)
            var words = place.split(separator: " ").filter { word in !word.contains(where: \.isNumber) }
            if words.count > 1, let last = words.last, isRegionCode(last) { words.removeLast() }
            if words.count == 1, isRegionCode(words[0]) { continue }
            let cleaned = words.joined(separator: " ")
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }

    /// A two-letter state or province code: "CA", "WA", "MI".
    private static func isRegionCode(_ word: Substring) -> Bool {
        word.count == 2 && word.allSatisfy { $0.isASCII && $0.isUppercase }
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
