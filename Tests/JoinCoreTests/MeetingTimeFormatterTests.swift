import Foundation
import Testing
@testable import JoinCore

struct MeetingTimeFormatterTests {
    typealias F = MenuBarFixtures

    /// Within a day; across midnight, times only, since DateIntervalFormatter would print full dates; beyond a
    /// day, with weekdays.
    @Test(arguments: [
        (F.date(5, 12), 1, "12:00 – 1:00 PM"),
        (F.date(5, 23, 30), 1, "11:30 PM – 12:30 AM"),
        (F.date(5, 23, 30), 48, "Mon 11:30 PM – Wed 11:30 PM"),
    ] as [(Date, Double, String)])
    func timeRange(from start: Date, hours: Double, expected: String) {
        let range = MeetingTimeFormatter.timeRange(
            start: start, end: start.addingTimeInterval(hours * 3600), locale: F.us, timeZone: F.calendar.timeZone
        )
        #expect(F.squash(range) == expected)
    }

    /// How a cut title ends: the space before the cut goes, so the ellipsis follows the last word. A length too
    /// short to cut leaves the text whole. Where titles are cut, at 24, is MenuBarPresenterTests'.
    @Test(arguments: [
        ("Board Meeting", 7, "Board…"),
        ("Board Meeting", 1, "Board Meeting"),
        ("Board Meeting", 0, "Board Meeting"),
    ])
    func truncatedTitles(_ text: String, maxLength: Int, expected: String) {
        #expect(MeetingTimeFormatter.truncate(text, to: maxLength) == expected)
    }
}
