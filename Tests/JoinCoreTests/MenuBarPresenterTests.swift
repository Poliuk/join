import XCTest
@testable import JoinCore

final class MenuBarPresenterTests: XCTestCase {
    typealias F = MenuBarFixtures

    private func status(
        _ meetings: [Meeting] = F.alertable,
        at now: Date,
        pause: PauseState = .active,
        showsNextEvent: Bool = true,
        showsTitles: Bool = false,
        startingSoonWindow: TimeInterval = MenuBarPresenter.startingSoonWindow,
        locale: Locale = F.us
    ) -> MenuBarStatus {
        var status = MenuBarPresenter.status(
            meetings: meetings, now: now, pauseState: pause,
            showsNextEvent: showsNextEvent, showsTitles: showsTitles,
            startingSoonWindow: startingSoonWindow,
            calendar: F.calendar, locale: locale
        )
        status.text = F.squash(status.text)
        status.accessibilityLabel = F.squash(status.accessibilityLabel) ?? ""
        return status
    }

    func testLaterTodayCountsDown() {
        let today = status(at: F.date(6, 10, 45))
        XCTAssertEqual(today.kind, .later)
        XCTAssertEqual(today.text, "Next in 2 h 15 min")
        XCTAssertEqual(today.accessibilityLabel, "Join!: Lunch with Lucía in 2 hours 15 minutes, at 1:00 PM")
    }

    func testOtherDaysShowTheDayAndTime() {
        let tomorrow = status(at: F.date(5, 21, 30))
        XCTAssertEqual(tomorrow.kind, .later)
        XCTAssertEqual(tomorrow.text, "Tomorrow at 1:00 PM")
        XCTAssertEqual(tomorrow.accessibilityLabel, "Join!: Lunch with Lucía tomorrow at 1:00 PM")

        let laterInTheWeek = status([F.review], at: F.date(5, 21, 30))
        XCTAssertEqual(laterInTheWeek.text, "In 2 days at 9:10 AM")
        XCTAssertEqual(laterInTheWeek.accessibilityLabel, "Join!: Revisión semanal in 2 days, Wednesday at 9:10 AM")
    }

    // Monday 10:00 AM, and the next meeting is next Monday at 9:00: VoiceOver names the date, not just "Monday".
    func testAWeekAheadCountsDays() {
        let nextWeek = status([F.nextMonday], at: F.date(5, 10))
        XCTAssertEqual(nextWeek.kind, .later)
        XCTAssertEqual(nextWeek.text, "In 7 days at 9:00 AM")
        XCTAssertEqual(nextWeek.accessibilityLabel, "Join!: Weekly in 7 days, \(F.formatted("EEEEdMMMM", day: 12, locale: F.us)) at 9:00 AM")
        XCTAssertEqual(status([F.nextMonday], at: F.date(5, 10), locale: F.gb).text, "In 7 days at 09:00")

        let sixDaysAhead = status([F.sunday], at: F.date(5, 10))
        XCTAssertEqual(sixDaysAhead.text, "In 6 days at 9:00 AM")
        XCTAssertEqual(sixDaysAhead.accessibilityLabel, "Join!: Brunch in 6 days, Sunday at 9:00 AM")
    }

    func testWithinTheHourCountsDownInMinutes() {
        let result = status(at: F.date(6, 12, 18))
        XCTAssertEqual(result.kind, .withinHour)
        XCTAssertEqual(result.text, "Next in 42 min")
        XCTAssertEqual(result.accessibilityLabel, "Join!: Lunch with Lucía in 42 minutes")
        XCTAssertEqual(status(at: F.date(6, 12)).text, "Next in 60 min")
        XCTAssertEqual(status(at: F.date(6, 11, 59, 59)).kind, .later)
    }

    // 3:56 PM: Workshop has run since 3:00 and Planning starts at 4:00. Starting soon wins over the meeting in progress.
    func testStartingSoonIsAnAccentPill() {
        let result = status(at: F.date(6, 15, 56))
        XCTAssertEqual(result.kind, .startingSoon)
        XCTAssertEqual(result.text, "Next in 4 min")
        XCTAssertEqual(result.accessibilityLabel, "Join!: Ana/Luis: Product Planning starts in 4 minutes")
        XCTAssertEqual(status(at: F.date(6, 15, 55)).kind, .startingSoon)
        XCTAssertEqual(status(at: F.date(6, 15, 54, 59)).text, "3 h 36 min left", "a second before the window, the running Workshop shows")
        XCTAssertEqual(status(at: F.date(6, 15, 59, 30)).text, "Next in 1 min")
    }

    func testInAMeetingShowsTimeLeftAndADrainingRing() {
        let result = status(at: F.date(6, 16, 20))
        XCTAssertEqual(result.text, "40 min left")
        XCTAssertEqual(result.accessibilityLabel, "Join!: Ana/Luis: Product Planning ends in 40 minutes")
        guard case .inMeeting(let remaining) = result.kind else { return XCTFail("expected inMeeting, got \(result.kind)") }
        XCTAssertEqual(remaining, 2.0 / 3.0, accuracy: 0.0001)

        let long = status([F.workshop], at: F.date(6, 16, 20))
        XCTAssertEqual(long.text, "3 h 10 min left")
    }

    func testPausedIsIconOnlyAndWinsOverEverything() {
        let paused = status(at: F.date(6, 15, 56), pause: .until(F.date(6, 16, 56)))
        XCTAssertEqual(paused.kind, .paused)
        XCTAssertNil(paused.text)
        XCTAssertEqual(paused.accessibilityLabel, "Join!: reminders paused")
        XCTAssertEqual(status(at: F.date(6, 16, 20), pause: .indefinitely).kind, .paused)
        XCTAssertEqual(status(at: F.date(6, 15, 56), pause: .until(F.date(6, 15, 50))).kind, .startingSoon)
    }

    func testNothingUpcomingIsIconOnly() {
        let result = status([], at: F.date(6, 10))
        XCTAssertEqual(result.kind, .idle)
        XCTAssertNil(result.text)
        XCTAssertEqual(status(at: F.date(9, 10)).kind, .idle)
    }

    // The caller passes only alertable meetings. An out-of-office block passed in (the user opted in) drives the bar like any meeting.
    func testOutOfOfficeBlocksPassedInDriveTheMenuBar() {
        XCTAssertEqual(status(F.week, at: F.date(6, 12, 28)).kind, .startingSoon)
    }

    func testIconOnlyWhenNextEventIsHiddenButKeepsTheState() {
        let soon = status(at: F.date(6, 15, 56), showsNextEvent: false, showsTitles: true)
        XCTAssertEqual(soon.kind, .startingSoon)
        XCTAssertNil(soon.text)
        XCTAssertEqual(soon.accessibilityLabel, "Join!: Ana/Luis: Product Planning starts in 4 minutes")
        XCTAssertNil(status(at: F.date(6, 12, 18), showsNextEvent: false).text)
        XCTAssertNil(status(at: F.date(6, 16, 20), showsNextEvent: false).text)
    }

    func testCurrentMeetingIsTheMostRecentlyStarted() {
        XCTAssertEqual(MenuBarPresenter.currentMeeting(in: F.alertable, now: F.date(6, 16, 20))?.id, "plan")
        XCTAssertEqual(MenuBarPresenter.currentMeeting(in: F.alertable, now: F.date(6, 15, 30))?.id, "val")
        XCTAssertNil(MenuBarPresenter.currentMeeting(in: F.alertable, now: F.date(6, 20)))
    }

    func testDurations() {
        // Panel `duration`, menu bar `steadyDuration` (keeps its width past an hour), VoiceOver `spokenDuration`.
        let cases: [(seconds: TimeInterval, panel: String, menuBar: String, spoken: String)] = [
            (1,                   "1 min",       "1 min",       "1 minute"),            // rounds up: never "0 min"
            (239.5,               "4 min",       "4 min",       "4 minutes"),
            (42 * 60,             "42 min",      "42 min",      "42 minutes"),
            (65 * 60,             "1 h 5 min",   "1 h 05 min",  "1 hour 5 minutes"),
            (120 * 60,            "2 h",         "2 h 00 min",  "2 hours"),
            (135 * 60,            "2 h 15 min",  "2 h 15 min",  "2 hours 15 minutes"),
            (11 * 3600 + 50 * 60, "11 h 50 min", "11 h 50 min", "11 hours 50 minutes"),
        ]
        for c in cases {
            XCTAssertEqual(MenuBarPresenter.duration(c.seconds), c.panel, "\(c.seconds) s")
            XCTAssertEqual(MenuBarPresenter.steadyDuration(c.seconds), c.menuBar, "\(c.seconds) s")
            XCTAssertEqual(MenuBarPresenter.spokenDuration(c.seconds), c.spoken, "\(c.seconds) s")
        }
    }

    func testRemainingFraction() {
        XCTAssertEqual(MenuBarPresenter.remainingFraction(of: F.planning, now: F.date(6, 16)), 1)
        XCTAssertEqual(MenuBarPresenter.remainingFraction(of: F.planning, now: F.date(6, 16, 30)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(MenuBarPresenter.remainingFraction(of: F.planning, now: F.date(6, 18)), 0)
        XCTAssertEqual(MenuBarPresenter.elapsedFraction(of: F.planning, now: F.date(6, 16, 15)), 0.25, accuracy: 0.0001)
    }

    func testPausedMessage() {
        let now = F.date(6, 10, 50)
        func message(_ state: PauseState) -> String? {
            F.squash(MenuBarPresenter.pausedMessage(state, now: now, calendar: F.calendar, locale: F.us))
        }
        XCTAssertNil(message(.active))
        XCTAssertNil(message(.until(F.date(6, 10, 49))))
        XCTAssertEqual(message(.until(F.date(6, 11, 50))), "Reminders paused until 11:50 AM")
        XCTAssertEqual(message(.until(F.date(7, 0))), "Reminders paused until tomorrow")
        XCTAssertEqual(message(.indefinitely), "Reminders paused")
    }

    func testHeaderDate() {
        func header(_ locale: Locale) -> String? {
            F.squash(MenuBarPresenter.headerDate(F.date(6, 10), calendar: F.calendar, locale: locale))
        }
        // The full weekday, day and month in each locale's order: "Tuesday 6 October", "Tuesday, October 6".
        XCTAssertEqual(header(F.gb), F.formatted("EEEEdMMMM", day: 6, locale: F.gb))
        XCTAssertEqual(header(F.us), F.formatted("EEEEdMMMM", day: 6, locale: F.us))
    }

    func testTitlesPrecedeTheTime() {
        let cases: [(meetings: [Meeting], now: Date, expected: String)] = [
            (F.alertable, F.date(6, 12, 18), "Lunch with Lucía · in 42 min"),            // within the hour
            (F.alertable, F.date(6, 10, 45), "Lunch with Lucía · in 2 h 15 min"),        // later today
            (F.alertable, F.date(5, 21, 30), "Lunch with Lucía · Tomorrow at 1:00 PM"),
            (F.alertable, F.date(5, 10), "Lunch with Lucía · Tomorrow at 1:00 PM"),     // 27 h ahead: days are calendar days
            ([F.review],  F.date(5, 21, 30), "Revisión semanal · In 2 days at 9:10 AM"),
            ([F.thursday], F.date(5, 9), "Design Crit · In 3 days at 10:00 AM"),         // 73 h ahead, still 3 days
            (F.alertable, F.date(6, 16, 20), "Ana/Luis: Product Plann… · 40 min left"),  // in a meeting; titles cut at 24
        ]
        for c in cases {
            XCTAssertEqual(status(c.meetings, at: c.now, showsTitles: true).text, c.expected, "at \(c.now)")
        }
    }

    func testMenuBarCountdownsKeepTheirWidth() {
        XCTAssertEqual(status(at: F.date(6, 11)).text, "Next in 2 h 00 min")              // Lunch at 1:00 PM
        XCTAssertEqual(status([F.workshop], at: F.date(6, 16, 25)).text, "3 h 05 min left") // ends 7:30 PM
    }

    func testTheStartingSoonWindowComesFromSettings() {
        // 12:52 PM, the next meeting starts at 1:00 PM: 8 minutes away.
        let now = F.date(6, 12, 52)
        XCTAssertEqual(status(at: now).kind, .withinHour)
        let wider = status(at: now, startingSoonWindow: 10 * 60)
        XCTAssertEqual(wider.kind, .startingSoon)
        XCTAssertEqual(wider.text, "Next in 8 min")
        XCTAssertEqual(status(at: F.date(6, 12, 58), startingSoonWindow: 60).kind, .withinHour, "1 minute: not yet at 2 minutes")
        XCTAssertEqual(status(at: F.date(6, 12, 59), startingSoonWindow: 60).kind, .startingSoon)
    }
}
