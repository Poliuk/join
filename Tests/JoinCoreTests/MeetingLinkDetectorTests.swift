import Foundation
import Testing
@testable import JoinCore

struct MeetingLinkDetectorTests {
    // In the notes only a provider's pattern can find a link; in the location the generic fallback would hide a broken one.
    @Test func eachProviderIsFoundInTheNotes() {
        let links = [
            "https://meet.google.com/abc-defg-hij",
            "https://us02web.zoom.us/j/1234567890?pwd=abc",
            "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%7d",
            "https://acme.webex.com/acme/j.php?MTID=m1",
        ]
        for link in links {
            let url = MeetingLinkDetector.joinURL(url: nil, location: nil, notes: "Join: \(link)\nMore info")
            #expect(url?.absoluteString == link, "\(link)")
        }
    }

    @Test func genericLinkInLocationIsUsed() {
        let url = MeetingLinkDetector.joinURL(url: nil, location: "https://example.com/room/42", notes: nil)
        #expect(url?.absoluteString == "https://example.com/room/42")
    }

    @Test func eventWebPageInURLFieldIsIgnored() {
        let url = MeetingLinkDetector.joinURL(url: URL(string: "https://calendar.google.com/event?eid=abc"), location: "Room 2", notes: "Agenda")
        #expect(url == nil)
    }

    @Test func knownProviderBeatsGenericLocationLink() {
        let url = MeetingLinkDetector.joinURL(url: nil, location: "https://example.com/directions", notes: "https://meet.google.com/abc-defg-hij")
        #expect(url?.host == "meet.google.com")
    }

    @Test func trailingPunctuationIsStripped() {
        let url = MeetingLinkDetector.joinURL(url: nil, location: nil, notes: "Call: https://zoom.us/j/999.")
        #expect(url?.absoluteString == "https://zoom.us/j/999")
    }
}
