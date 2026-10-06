import Foundation

/// Finds a video-call link in an event's URL, location, or notes.
public enum MeetingLinkDetector {
    public struct Provider: Sendable, Hashable {
        public let name: String
        public let pattern: String
    }

    /// Ordered: a match from an earlier provider wins regardless of which field it appears in.
    public static let providers: [Provider] = [
        Provider(
            name: "Google Meet",
            pattern: #"https://meet\.google\.com/(?:[a-z]{3}-[a-z]{4}-[a-z]{3}|lookup/[A-Za-z0-9_-]+)(?:\?[^\s<>"')]*)?"#
        ),
        Provider(
            name: "Zoom",
            pattern: #"https://(?:[A-Za-z0-9.-]+\.)?zoom\.(?:us|com)/(?:j|my|s|w)/[^\s<>"')]+"#
        ),
        Provider(
            name: "Microsoft Teams",
            pattern: #"https://teams\.(?:microsoft\.com/l/meetup-join|live\.com/meet)/[^\s<>"')]+"#
        ),
        Provider(
            name: "Webex",
            pattern: #"https://[A-Za-z0-9.-]+\.webex\.com/[^\s<>"')]+"#
        ),
    ]

    /// Any https link in the *location* field is treated as the way into the meeting.
    /// The URL field is deliberately excluded: calendar backends often put the event's own web page there.
    private static let genericLocationPattern = #"https://[^\s<>"')]+"#

    public static func joinURL(in meeting: Meeting) -> URL? {
        joinURL(url: meeting.url, location: meeting.location, notes: meeting.notes)
    }

    public static func joinURL(url: URL?, location: String?, notes: String?) -> URL? {
        let fields = [url?.absoluteString, location, notes].compactMap { $0 }
        for provider in providers {
            for field in fields {
                if let match = firstMatch(of: provider.pattern, in: field), let found = URL(string: match) {
                    return found
                }
            }
        }
        if let location, let match = firstMatch(of: genericLocationPattern, in: location) {
            return URL(string: match)
        }
        return nil
    }

    private static func firstMatch(of pattern: String, in text: String) -> String? {
        guard let regex = regexCache[pattern] else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), let found = Range(match.range, in: text) else {
            return nil
        }
        var result = String(text[found])
        while let last = result.last, ".,;:!?".contains(last) { result.removeLast() }
        return result
    }

    private static let regexCache: [String: NSRegularExpression] = {
        var cache: [String: NSRegularExpression] = [:]
        for pattern in providers.map(\.pattern) + [genericLocationPattern] {
            cache[pattern] = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
        return cache
    }()
}
