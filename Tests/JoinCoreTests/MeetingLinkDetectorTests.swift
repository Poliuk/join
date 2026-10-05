import XCTest
@testable import JoinCore

final class MeetingLinkDetectorTests: XCTestCase {
    func testGoogleMeetInNotes() {
        let url = MeetingLinkDetector.joinURL(url: nil, location: nil, notes: "Join with Google Meet: https://meet.google.com/abc-defg-hij\nMore info")
        XCTAssertEqual(url?.absoluteString, "https://meet.google.com/abc-defg-hij")
    }

    func testZoomInLocation() {
        let url = MeetingLinkDetector.joinURL(url: nil, location: "https://us02web.zoom.us/j/1234567890?pwd=abc", notes: nil)
        XCTAssertEqual(url?.absoluteString, "https://us02web.zoom.us/j/1234567890?pwd=abc")
        XCTAssertEqual(MeetingLinkDetector.providerName(for: url!), "Zoom")
    }

    func testTeams() {
        let link = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%7d"
        let url = MeetingLinkDetector.joinURL(url: nil, location: nil, notes: "Click here to join: \(link)")
        XCTAssertEqual(url?.absoluteString, link)
        XCTAssertEqual(MeetingLinkDetector.providerName(for: url!), "Microsoft Teams")
    }

    func testWebex() {
        let url = MeetingLinkDetector.joinURL(url: nil, location: "https://acme.webex.com/acme/j.php?MTID=m1", notes: nil)
        XCTAssertEqual(MeetingLinkDetector.providerName(for: url!), "Webex")
    }

    func testGenericLinkInLocationIsUsed() {
        let url = MeetingLinkDetector.joinURL(url: nil, location: "https://example.com/room/42", notes: nil)
        XCTAssertEqual(url?.absoluteString, "https://example.com/room/42")
        XCTAssertNil(MeetingLinkDetector.providerName(for: url!))
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

    func testNoLink() {
        XCTAssertNil(MeetingLinkDetector.joinURL(url: nil, location: "Conference Room A", notes: "Bring snacks"))
    }
}
