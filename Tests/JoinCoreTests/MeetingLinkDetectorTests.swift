import XCTest
@testable import JoinCore

final class MeetingLinkDetectorTests: XCTestCase {
    // In the notes only a provider's pattern can find a link; in the location the generic fallback would hide a broken one.
    func testEachProviderIsFoundInTheNotes() {
        let links = [
            "https://meet.google.com/abc-defg-hij",
            "https://us02web.zoom.us/j/1234567890?pwd=abc",
            "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%7d",
            "https://acme.webex.com/acme/j.php?MTID=m1",
        ]
        for link in links {
            let url = MeetingLinkDetector.joinURL(url: nil, location: nil, notes: "Join: \(link)\nMore info")
            XCTAssertEqual(url?.absoluteString, link, link)
        }
    }

    func testGenericLinkInLocationIsUsed() {
        let url = MeetingLinkDetector.joinURL(url: nil, location: "https://example.com/room/42", notes: nil)
        XCTAssertEqual(url?.absoluteString, "https://example.com/room/42")
    }

    func testEventWebPageInURLFieldIsIgnored() {
        let url = MeetingLinkDetector.joinURL(url: URL(string: "https://calendar.google.com/event?eid=abc"), location: "Room 2", notes: "Agenda")
        XCTAssertNil(url)
    }

    func testKnownProviderBeatsGenericLocationLink() {
        let url = MeetingLinkDetector.joinURL(url: nil, location: "https://example.com/directions", notes: "https://meet.google.com/abc-defg-hij")
        XCTAssertEqual(url?.host, "meet.google.com")
    }

    func testTrailingPunctuationIsStripped() {
        let url = MeetingLinkDetector.joinURL(url: nil, location: nil, notes: "Call: https://zoom.us/j/999.")
        XCTAssertEqual(url?.absoluteString, "https://zoom.us/j/999")
    }
}
