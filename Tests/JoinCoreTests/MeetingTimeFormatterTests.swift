import XCTest
@testable import JoinCore

final class MeetingTimeFormatterTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCompactDuration() {
        XCTAssertEqual(MeetingTimeFormatter.compactDuration(30), "<1m")
        XCTAssertEqual(MeetingTimeFormatter.compactDuration(12 * 60), "12m")
        XCTAssertEqual(MeetingTimeFormatter.compactDuration(65 * 60), "1h 5m")
        XCTAssertEqual(MeetingTimeFormatter.compactDuration(2 * 3600), "2h")
        XCTAssertEqual(MeetingTimeFormatter.compactDuration(3 * 86400), "3d")
    }

    func testPreciseDuration() {
        XCTAssertEqual(MeetingTimeFormatter.preciseDuration(45), "45s")
        XCTAssertEqual(MeetingTimeFormatter.preciseDuration(133), "2m 13s")
        XCTAssertEqual(MeetingTimeFormatter.preciseDuration(3900), "1h 05m")
    }

    func testCountdown() {
        let start = now.addingTimeInterval(133)
        let end = start.addingTimeInterval(3600)
        XCTAssertEqual(MeetingTimeFormatter.countdown(start: start, end: end, now: now), "Starts in 2m 13s")
        XCTAssertEqual(MeetingTimeFormatter.countdown(start: start, end: end, now: start.addingTimeInterval(10)), "Started just now")
        XCTAssertEqual(MeetingTimeFormatter.countdown(start: start, end: end, now: start.addingTimeInterval(300)), "Started 5m ago")
        XCTAssertEqual(MeetingTimeFormatter.countdown(start: start, end: end, now: end), "Ended")
    }

    func testRowDetail() {
        let start = now.addingTimeInterval(12 * 60)
        let end = start.addingTimeInterval(3600)
        XCTAssertEqual(MeetingTimeFormatter.rowDetail(start: start, end: end, now: now), "in 12m")
        XCTAssertEqual(MeetingTimeFormatter.rowDetail(start: start, end: end, now: start.addingTimeInterval(60)), "59m left")
        XCTAssertNil(MeetingTimeFormatter.rowDetail(start: start, end: end, now: end))
    }

    func testTruncate() {
        XCTAssertEqual(MeetingTimeFormatter.truncate("Board Meeting", to: 24), "Board Meeting")
        XCTAssertEqual(MeetingTimeFormatter.truncate("A very long meeting title indeed", to: 10), "A very lo…")
    }

    func testMenuBarTitle() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12))!

        XCTAssertNil(MeetingTimeFormatter.menuBarTitle(for: nil, now: noon, calendar: calendar))

        let ongoing = Meeting(id: "a", title: "Board Meeting", start: noon.addingTimeInterval(-600), end: noon.addingTimeInterval(600))
        XCTAssertEqual(MeetingTimeFormatter.menuBarTitle(for: ongoing, now: noon, calendar: calendar), "Board Meeting, now")

        let soon = Meeting(id: "b", title: "Design Sync", start: noon.addingTimeInterval(12 * 60), end: noon.addingTimeInterval(72 * 60))
        XCTAssertEqual(MeetingTimeFormatter.menuBarTitle(for: soon, now: noon, calendar: calendar), "Design Sync, in 12m")

        let tomorrow = Meeting(id: "c", title: "Standup", start: noon.addingTimeInterval(20 * 3600), end: noon.addingTimeInterval(21 * 3600))
        let title = MeetingTimeFormatter.menuBarTitle(for: tomorrow, now: noon, calendar: calendar, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(squashWhitespace(title ?? ""), "Standup, tomorrow 8:00 AM")

        let farAway = Meeting(id: "d", title: "Offsite", start: noon.addingTimeInterval(3 * 86400), end: noon.addingTimeInterval(3 * 86400 + 3600))
        XCTAssertNil(MeetingTimeFormatter.menuBarTitle(for: farAway, now: noon, calendar: calendar))
    }

    func testTimeRange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12))!
        let range = MeetingTimeFormatter.timeRange(start: noon, end: noon.addingTimeInterval(3600), locale: Locale(identifier: "en_US"), timeZone: calendar.timeZone)
        XCTAssertEqual(squashWhitespace(range), "12:00 – 1:00 PM")
    }

    func testDayHeading() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12))!
        XCTAssertEqual(MeetingTimeFormatter.dayHeading(for: noon.addingTimeInterval(3600), now: noon, calendar: calendar), "Today")
        XCTAssertEqual(MeetingTimeFormatter.dayHeading(for: noon.addingTimeInterval(86400), now: noon, calendar: calendar), "Tomorrow")
        XCTAssertEqual(
            MeetingTimeFormatter.dayHeading(for: noon.addingTimeInterval(3 * 86400), now: noon, calendar: calendar, locale: Locale(identifier: "en_US")),
            "Thu, Oct 8"
        )
    }

    /// Foundation formats times with narrow no-break spaces; normalise before comparing.
    private func squashWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
