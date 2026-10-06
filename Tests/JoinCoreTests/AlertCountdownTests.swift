import XCTest
@testable import JoinCore

final class AlertCountdownTests: XCTestCase {
    typealias F = MenuBarFixtures

    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var end: Date { start.addingTimeInterval(3 * 3600) }

    private func text(_ offset: TimeInterval) -> String {
        AlertCountdown.text(start: start, end: end, now: start.addingTimeInterval(offset))
    }

    func testBeforeTheStartCountsDownInMinutesAndSeconds() {
        XCTAssertEqual(text(-179), "Starts in 2:59")
        XCTAssertEqual(text(-180), "Starts in 3:00")
        XCTAssertEqual(text(-179.4), "Starts in 3:00", "Rounded up")
        XCTAssertEqual(text(-0.2), "Starts in 0:01", "Never 0:00 before the start")
        XCTAssertEqual(text(-3700), "Starts in 1:01:40")
    }

    func testAfterTheStart() {
        XCTAssertEqual(text(0), "Starting now")
        XCTAssertEqual(text(59), "Starting now")
        XCTAssertEqual(text(60), "Started 1 min ago")
        XCTAssertEqual(text(3 * 60 + 30), "Started 3 min ago")
        XCTAssertEqual(text(3600), "Started 1 hr ago")
        XCTAssertEqual(text(3900), "Started 1 hr 5 min ago")
        XCTAssertEqual(text(3 * 3600), "Ended")
    }

    func testPhasesAndJoinTitle() {
        XCTAssertEqual(AlertCountdown.phase(start: start, end: end, now: start.addingTimeInterval(-1)), .before)
        XCTAssertEqual(AlertCountdown.phase(start: start, end: end, now: start), .starting)
        XCTAssertEqual(AlertCountdown.phase(start: start, end: end, now: start.addingTimeInterval(60)), .started)
        XCTAssertEqual(AlertCountdown.phase(start: start, end: end, now: end), .ended)
        XCTAssertEqual(AlertCountdown.joinTitle(for: .before), "Join")
        XCTAssertEqual(AlertCountdown.joinTitle(for: .starting), "Join now")
        XCTAssertEqual(AlertCountdown.joinTitle(for: .started), "Join now")
    }

    func testSnoozeLabels() {
        // Seconds to whole minutes, never 0; the wording itself is SettingsOptions' (testDurationTitles).
        let cases: [(seconds: TimeInterval, label: String, spoken: String)] = [
            (30, "1 min", "Snooze 1 minute"), (60, "1 min", "Snooze 1 minute"),
            (300, "5 min", "Snooze 5 minutes"), (3600, "1 hr", "Snooze 1 hour"),
        ]
        for c in cases {
            XCTAssertEqual(AlertCountdown.snoozeLabel(c.seconds), c.label, "\(c.seconds)s")
            XCTAssertEqual(AlertCountdown.snoozeAccessibilityLabel(c.seconds), c.spoken, "\(c.seconds)s")
        }
        let presets = SettingsOptions.snoozeMinutes.map { TimeInterval($0 * 60) }
        XCTAssertEqual(Array(SettingsOptions.alertOffers(snoozeDurations: presets).dropLast()),
                       presets.map(AlertCountdown.snoozeLabel), "Settings' chips preview the alert's buttons")
    }

    func testSnoozeUntilStartLabels() {
        XCTAssertEqual(AlertCountdown.snoozeUntilStartLabel, "At event start")
        XCTAssertEqual(F.squash(AlertCountdown.snoozeUntilStartAccessibilityLabel(F.date(5, 14), locale: F.us, timeZone: F.calendar.timeZone)),
                       "Snooze until the event starts at 2:00 PM")
    }
}
