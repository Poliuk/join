import XCTest
@testable import JoinCore

final class MeetingFilterTests: XCTestCase {
    func testAllDayEventsAreExcluded() {
        XCTAssertFalse(MeetingFilter.shouldInclude(isAllDay: true, isCanceled: false, myStatus: .accepted))
    }

    func testCanceledEventsAreExcluded() {
        XCTAssertFalse(MeetingFilter.shouldInclude(isAllDay: false, isCanceled: true, myStatus: .accepted))
    }

    func testDeclinedEventsAreExcluded() {
        XCTAssertFalse(MeetingFilter.shouldInclude(isAllDay: false, isCanceled: false, myStatus: .declined))
    }

    func testTentativeAndUnknownAreIncluded() {
        XCTAssertTrue(MeetingFilter.shouldInclude(isAllDay: false, isCanceled: false, myStatus: .tentative))
        XCTAssertTrue(MeetingFilter.shouldInclude(isAllDay: false, isCanceled: false, myStatus: .unknown))
    }

    func testOccurrenceIDIncludesStart() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(Meeting.occurrenceID(eventIdentifier: "evt", start: start), "evt@1800000000")
        XCTAssertNotEqual(
            Meeting.occurrenceID(eventIdentifier: "evt", start: start),
            Meeting.occurrenceID(eventIdentifier: "evt", start: start.addingTimeInterval(86400))
        )
    }
}
