import Foundation
import Testing
@testable import JoinCore

struct AlertCountdownTests {
    typealias F = MenuBarFixtures

    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var end: Date { start.addingTimeInterval(3 * 3600) }

    private func text(_ offset: TimeInterval) -> String {
        AlertCountdown.text(start: start, end: end, now: start.addingTimeInterval(offset))
    }

    @Test func beforeTheStartCountsDownInMinutesAndSeconds() {
        #expect(text(-179) == "Starts in 2:59")
        #expect(text(-180) == "Starts in 3:00")
        #expect(text(-179.4) == "Starts in 3:00", "Rounded up")
        #expect(text(-0.2) == "Starts in 0:01", "Never 0:00 before the start")
        #expect(text(-3700) == "Starts in 1:01:40")
    }

    @Test func afterTheStart() {
        #expect(text(0) == "Starting now")
        #expect(text(59) == "Starting now")
        #expect(text(60) == "Started 1 min ago")
        #expect(text(3 * 60 + 30) == "Started 3 min ago")
        #expect(text(3600) == "Started 1 hr ago")
        #expect(text(3900) == "Started 1 hr 5 min ago")
        #expect(text(3 * 3600) == "Ended")
    }

    @Test func phasesAndJoinTitle() {
        #expect(AlertCountdown.phase(start: start, end: end, now: start.addingTimeInterval(-1)) == .before)
        #expect(AlertCountdown.phase(start: start, end: end, now: start) == .starting)
        #expect(AlertCountdown.phase(start: start, end: end, now: start.addingTimeInterval(60)) == .started)
        #expect(AlertCountdown.phase(start: start, end: end, now: end) == .ended)
        #expect(AlertCountdown.joinTitle(for: .before) == "Join")
        #expect(AlertCountdown.joinTitle(for: .starting) == "Join now")
        #expect(AlertCountdown.joinTitle(for: .started) == "Join now")
    }

    @Test func snoozeLabels() {
        // Seconds to whole minutes, never 0; the wording itself is SettingsOptions' (see SettingsOptionsTests' duration titles).
        let cases: [(seconds: TimeInterval, label: String, spoken: String)] = [
            (30, "1 min", "Snooze 1 minute"), (60, "1 min", "Snooze 1 minute"),
            (300, "5 min", "Snooze 5 minutes"), (3600, "1 hr", "Snooze 1 hour"),
        ]
        for c in cases {
            #expect(AlertCountdown.snoozeLabel(c.seconds) == c.label, "\(c.seconds)s")
            #expect(AlertCountdown.snoozeAccessibilityLabel(c.seconds) == c.spoken, "\(c.seconds)s")
        }
        let presets = SettingsOptions.snoozeMinutes.map { TimeInterval($0 * 60) }
        #expect(presets.map(AlertCountdown.snoozeLabel) == SettingsOptions.snoozeMinutes.map(SettingsOptions.shortDurationTitle(minutes:)))
    }

    /// Both snooze buttons set to the same time would show two identical buttons.
    @Test func snoozeChoicesShowEachDurationOnce() {
        #expect(AlertCountdown.snoozeChoices([60, 300]) == [60, 300])
        #expect(AlertCountdown.snoozeChoices([300, 60]) == [300, 60], "in Settings' order")
        #expect(AlertCountdown.snoozeChoices([300, 300]) == [300])
        #expect(AlertCountdown.snoozeChoices([60, 89]) == [60], "both read \"1 min\"")
        #expect(AlertCountdown.snoozeChoices([]) == [])
    }

    @Test func snoozeUntilStartLabels() {
        #expect(AlertCountdown.snoozeUntilStartLabel == "At event start")
        #expect(F.squash(AlertCountdown.snoozeUntilStartAccessibilityLabel(F.date(5, 14), locale: F.us, timeZone: F.calendar.timeZone))
                == "Snooze until the event starts at 2:00 PM")
    }
}
