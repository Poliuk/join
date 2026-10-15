import Foundation
import Testing
@testable import JoinCore

struct MeetingLinkDetectorTests {
    static let meet = "https://meet.google.com/abc-defg-hij"
    static let teams = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%7d"

    /// The link Join opens, from an event's URL field, location and notes. A provider's pattern is searched in every
    /// field, and an earlier provider wins whichever field it's in. Only the location falls back to any https link:
    /// the URL field often holds the event's own web page, and in the notes the fallback would hide a broken pattern.
    @Test(arguments: [
        // Each provider in the notes.
        ("Google Meet", nil, nil, "Join: \(meet)\nMore info", meet),
        ("Google Meet, looked up", nil, nil, "Join: https://meet.google.com/lookup/abc123_-x\nMore info", "https://meet.google.com/lookup/abc123_-x"),
        ("Zoom", nil, nil, "Join: https://us02web.zoom.us/j/1234567890?pwd=abc\nMore info", "https://us02web.zoom.us/j/1234567890?pwd=abc"),
        ("Zoom, a personal room", nil, nil, "Join: https://zoom.us/my/ana.garcia\nMore info", "https://zoom.us/my/ana.garcia"),
        ("Zoom, a webinar", nil, nil, "Join: https://acme.zoom.com/w/98765432?tk=abc\nMore info", "https://acme.zoom.com/w/98765432?tk=abc"),
        ("Zoom, a start link", nil, nil, "Join: https://zoom.com/s/123456789\nMore info", "https://zoom.com/s/123456789"),
        ("Microsoft Teams", nil, nil, "Join: \(teams)\nMore info", teams),
        ("Microsoft Teams, personal", nil, nil, "Join: https://teams.live.com/meet/9876543210?p=abc\nMore info", "https://teams.live.com/meet/9876543210?p=abc"),
        ("Webex", nil, nil, "Join: https://acme.webex.com/acme/j.php?MTID=m1\nMore info", "https://acme.webex.com/acme/j.php?MTID=m1"),
        // Notes in HTML, as Outlook and Exchange write them: the link ends at the quote or the bracket.
        ("a Teams link in HTML", nil, nil, "<a href=\"\(teams)\">Join the meeting now</a>", teams),
        ("a Zoom link in angle brackets", nil, nil, "Join Zoom Meeting <https://zoom.us/j/999>", "https://zoom.us/j/999"),
        // The URL field.
        ("a Teams link in the URL field", teams, "Microsoft Teams Meeting", nil, teams),
        ("the event's web page in the URL field", "https://calendar.google.com/event?eid=abc", "Room 2", "Agenda", nil),
        ("an earlier provider in another field", "https://zoom.us/j/999", nil, "Join: \(meet)", meet),
        // The location.
        ("any link in the location", nil, "https://example.com/room/42", nil, "https://example.com/room/42"),
        ("a provider beats a link in the location", nil, "https://example.com/directions", meet, meet),
        ("trailing punctuation", nil, nil, "Call: https://zoom.us/j/999.", "https://zoom.us/j/999"),
    ] as [(String, String?, String?, String?, String?)])
    func joinURL(_ name: String, url: String?, location: String?, notes: String?, expected: String?) throws {
        let found = MeetingLinkDetector.joinURL(url: try url.map { try #require(URL(string: $0)) }, location: location, notes: notes)
        #expect(found?.absoluteString == expected)
    }
}
