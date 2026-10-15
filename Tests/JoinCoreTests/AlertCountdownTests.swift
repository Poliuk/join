import Foundation
import Testing
@testable import JoinCore

struct AlertCountdownTests {
    typealias F = MenuBarFixtures

    /// The countdown above the title and the Join button's label, at `offset` seconds from the start of a
    /// three-hour meeting. Before the start the clock is rounded up, so it never reads 0:00 early; the first
    /// minute after it is "Starting now"; then whole minutes, rounded down, until the end.
    @Test(arguments: [
        (-179, "Starts in 2:59", "Join"),
        (-180, "Starts in 3:00", "Join"),
        (-179.4, "Starts in 3:00", "Join"),
        (-0.2, "Starts in 0:01", "Join"),
        (-3700, "Starts in 1:01:40", "Join"),
        (0, "Starting now", "Join now"),
        (59, "Starting now", "Join now"),
        (60, "Started 1 min ago", "Join now"),
        (3 * 60 + 30, "Started 3 min ago", "Join now"),
        (3600, "Started 1 hr ago", "Join now"),
        (3900, "Started 1 hr 5 min ago", "Join now"),
        (3 * 3600, "Ended", "Join now"),
    ] as [(TimeInterval, String, String)])
    func countdownTextAndJoinTitle(offset: TimeInterval, text: String, joinTitle: String) {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(3 * 3600)
        let now = start.addingTimeInterval(offset)
        #expect(AlertCountdown.text(start: start, end: end, now: now) == text)
        #expect(AlertCountdown.joinTitle(for: AlertCountdown.phase(start: start, end: end, now: now)) == joinTitle)
    }

    /// Seconds to whole minutes, never 0; the wording itself is SettingsOptions' (see SettingsOptionsTests' duration titles).
    @Test(arguments: [
        (30, "1 min", "Snooze 1 minute"),
        (60, "1 min", "Snooze 1 minute"),
        (300, "5 min", "Snooze 5 minutes"),
        (3600, "1 hr", "Snooze 1 hour"),
    ] as [(TimeInterval, String, String)])
    func snoozeLabels(seconds: TimeInterval, label: String, spoken: String) {
        #expect(AlertCountdown.snoozeLabel(seconds) == label)
        #expect(AlertCountdown.snoozeAccessibilityLabel(seconds) == spoken)
    }

    /// Both snooze buttons set to the same time would show two identical buttons: each label once, in Settings' order.
    @Test(arguments: [
        ("two durations", [60, 300], [60, 300]),
        ("in Settings' order", [300, 60], [300, 60]),
        ("the same duration twice", [300, 300], [300]),
        ("both read \"1 min\"", [60, 89], [60]),
        ("none", [], []),
    ] as [(String, [TimeInterval], [TimeInterval])])
    func snoozeChoicesShowEachDurationOnce(_ name: String, durations: [TimeInterval], expected: [TimeInterval]) {
        #expect(AlertCountdown.snoozeChoices(durations) == expected)
    }

    @Test func snoozeUntilStartLabels() {
        #expect(AlertCountdown.snoozeUntilStartLabel == "At event start")
        #expect(F.squash(AlertCountdown.snoozeUntilStartAccessibilityLabel(F.date(5, 14), locale: F.us, timeZone: F.calendar.timeZone))
                == "Snooze until the event starts at 2:00 PM")
    }
}
