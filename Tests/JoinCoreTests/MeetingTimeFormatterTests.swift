import XCTest
@testable import JoinCore

final class MeetingTimeFormatterTests: XCTestCase {
    typealias F = MenuBarFixtures

    func testTruncate() {
        XCTAssertEqual(MeetingTimeFormatter.truncate("Board Meeting", to: 24), "Board Meeting")
        XCTAssertEqual(MeetingTimeFormatter.truncate("A very long meeting title indeed", to: 10), "A very lo…")
    }

    func testTimeRange() {
        func range(from start: Date, hours: Double) -> String? {
            F.squash(MeetingTimeFormatter.timeRange(start: start, end: start.addingTimeInterval(hours * 3600), locale: F.us, timeZone: F.calendar.timeZone))
        }
        XCTAssertEqual(range(from: F.date(5, 12), hours: 1), "12:00 – 1:00 PM", "within a day")
        XCTAssertEqual(range(from: F.date(5, 23, 30), hours: 1), "11:30 PM – 12:30 AM", "across midnight: times only, no dates")
        XCTAssertEqual(range(from: F.date(5, 23, 30), hours: 48), "Mon 11:30 PM – Wed 11:30 PM", "beyond a day: weekdays")
    }
}
