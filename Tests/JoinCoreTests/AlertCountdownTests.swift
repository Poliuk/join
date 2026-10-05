import XCTest
@testable import JoinCore

final class AlertCountdownTests: XCTestCase {
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
        XCTAssertEqual(AlertCountdown.snoozeLabel(60), "1 min")
        XCTAssertEqual(AlertCountdown.snoozeLabel(300), "5 min")
        XCTAssertEqual(AlertCountdown.snoozeAccessibilityLabel(60), "Snooze 1 minute")
        XCTAssertEqual(AlertCountdown.snoozeAccessibilityLabel(300), "Snooze 5 minutes")
        XCTAssertEqual(AlertCountdown.snoozeLabel(30), "1 min", "Never 0 min")
        XCTAssertEqual(AlertCountdown.snoozeAccessibilityLabel(30), "Snooze 1 minute")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let twoPM = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 14))!
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(squashWhitespace(AlertCountdown.snoozeUntilStartLabel(twoPM, locale: locale, timeZone: calendar.timeZone)), "At 2:00 PM")
        XCTAssertEqual(
            squashWhitespace(AlertCountdown.snoozeUntilStartAccessibilityLabel(twoPM, locale: locale, timeZone: calendar.timeZone)),
            "Snooze until 2:00 PM"
        )
    }

    func testSnoozeLabelsMatchTheSettingsWording() {
        XCTAssertEqual(AlertCountdown.snoozeLabel(3600), "1 hr")
        XCTAssertEqual(AlertCountdown.snoozeAccessibilityLabel(3600), "Snooze 1 hour")
        XCTAssertEqual(AlertCountdown.snoozeLabel(7200), "2 hr")
        XCTAssertEqual(AlertCountdown.snoozeAccessibilityLabel(7200), "Snooze 2 hours")
        XCTAssertEqual(AlertCountdown.snoozeLabel(90 * 60), "90 min")
        XCTAssertEqual(AlertCountdown.snoozeAccessibilityLabel(90 * 60), "Snooze 90 minutes")

        let durations: [TimeInterval] = SettingsOptions.snoozeMinutes.map { TimeInterval($0 * 60) }
        let offers = SettingsOptions.alertOffers(snoozeDurations: durations)
        XCTAssertEqual(Array(offers.prefix(durations.count)), durations.map(AlertCountdown.snoozeLabel), "Settings' chips preview the alert's buttons")
    }

    private func squashWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
