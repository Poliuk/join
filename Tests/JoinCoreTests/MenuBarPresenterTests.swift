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
        locale: Locale = F.us
    ) -> MenuBarStatus {
        var status = MenuBarPresenter.status(
            meetings: meetings, now: now, pauseState: pause,
            showsNextEvent: showsNextEvent, showsTitles: showsTitles,
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
        XCTAssertEqual(nextWeek.accessibilityLabel, "Join!: Weekly in 7 days, Monday, October 12 at 9:00 AM")
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

    func testStartingSoonIsAnAccentPill() {
        let result = status(at: F.date(6, 15, 56))
        XCTAssertEqual(result.kind, .startingSoon)
        XCTAssertEqual(result.text, "Next in 4 min")
        XCTAssertEqual(result.accessibilityLabel, "Join!: Ana/Luis: Product Planning starts in 4 minutes")
        XCTAssertEqual(status(at: F.date(6, 15, 55)).kind, .startingSoon)
        XCTAssertEqual(status(at: F.date(6, 15, 54, 59)).kind, .inMeeting(remaining: MenuBarPresenter.remainingFraction(of: F.workshop, now: F.date(6, 15, 54, 59))))
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

    func testStartingSoonWinsOverAMeetingInProgress() {
        XCTAssertEqual(status(at: F.date(6, 15, 58)).kind, .startingSoon)
    }

    func testNothingUpcomingIsIconOnly() {
        let result = status([], at: F.date(6, 10))
        XCTAssertEqual(result.kind, .idle)
        XCTAssertNil(result.text)
        XCTAssertEqual(status(at: F.date(9, 10)).kind, .idle)
    }

    func testOutOfOfficeIsIgnoredWhenNotAlertable() {
        XCTAssertEqual(status(at: F.date(6, 12, 28)).text, "Next in 32 min")
        XCTAssertEqual(status(F.week, at: F.date(6, 12, 28)).kind, .startingSoon)
    }

    func testEventTitlesArePrependedOnlyWhenEnabled() {
        XCTAssertEqual(status(at: F.date(6, 12, 18), showsTitles: true).text, "Lunch with Lucía · in 42 min")
        XCTAssertEqual(status(at: F.date(6, 16, 20), showsTitles: true).text, "Ana/Luis: Product Plann… · 40 min left")
        XCTAssertEqual(status(at: F.date(5, 21, 30), showsTitles: true).text, "Lunch with Lucía · Tomorrow at 1:00 PM")
        XCTAssertEqual(status(at: F.date(5, 21, 30), showsTitles: false).text, "Tomorrow at 1:00 PM")
        let long = Meeting(id: "x", title: "A very long meeting title that goes on", start: F.date(6, 10, 30), end: F.date(6, 11))
        XCTAssertEqual(status([long], at: F.date(6, 10), showsTitles: true).text, "A very long meeting tit… · in 30 min")
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
        XCTAssertEqual(MenuBarPresenter.duration(42 * 60), "42 min")
        XCTAssertEqual(MenuBarPresenter.duration(135 * 60), "2 h 15 min")
        XCTAssertEqual(MenuBarPresenter.duration(120 * 60), "2 h")
        XCTAssertEqual(MenuBarPresenter.duration(15.5 * 3600), "15 h 30 min")
        XCTAssertEqual(MenuBarPresenter.duration(239.5), "4 min")
        XCTAssertEqual(MenuBarPresenter.duration(1), "1 min")
        XCTAssertEqual(MenuBarPresenter.minutes(60 * 60), "60 min")
        XCTAssertEqual(MenuBarPresenter.spokenDuration(60), "1 minute")
        XCTAssertEqual(MenuBarPresenter.spokenDuration(4 * 60), "4 minutes")
        XCTAssertEqual(MenuBarPresenter.spokenDuration(65 * 60), "1 hour 5 minutes")
        XCTAssertEqual(MenuBarPresenter.spokenDuration(120 * 60), "2 hours")
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
        XCTAssertEqual(F.squash(MenuBarPresenter.headerDate(F.date(6, 10), calendar: F.calendar, locale: F.gb)), "Tuesday 6 October")
        XCTAssertEqual(F.squash(MenuBarPresenter.headerDate(F.date(6, 10), calendar: F.calendar, locale: F.us)), "Tuesday, October 6")
    }

    func testTitlesPrecedeTheTime() {
        let base = F.date(5, 10)
        let inTwoHours = Meeting(id: "a", title: "Design Sync", start: base.addingTimeInterval(2 * 3600 + 15 * 60), end: base.addingTimeInterval(4 * 3600))
        XCTAssertEqual(status([inTwoHours], at: base, showsTitles: true).text, "Design Sync · in 2 h 15 min")
        XCTAssertEqual(status([inTwoHours], at: base, showsTitles: false).text, "Next in 2 h 15 min")

        let inThreeDays = Meeting(id: "b", title: "Offsite", start: base.addingTimeInterval(3 * 86400 + 3600), end: base.addingTimeInterval(3 * 86400 + 7200))
        XCTAssertEqual(status([inThreeDays], at: base, showsTitles: true).text, "Offsite · In 3 days at 11:00 AM")
        let inADay = Meeting(id: "c", title: "Standup", start: base.addingTimeInterval(86400 + 60), end: base.addingTimeInterval(86400 + 1800))
        XCTAssertEqual(status([inADay], at: base, showsTitles: true).text, "Standup · Tomorrow at 10:01 AM")
    }

    func testMenuBarCountdownsKeepTheirWidth() {
        XCTAssertEqual(MenuBarPresenter.steadyDuration(2 * 3600), "2 h 00 min")
        XCTAssertEqual(MenuBarPresenter.steadyDuration(2 * 3600 + 5 * 60), "2 h 05 min")
        XCTAssertEqual(MenuBarPresenter.steadyDuration(11 * 3600 + 50 * 60), "11 h 50 min")
        XCTAssertEqual(MenuBarPresenter.steadyDuration(42 * 60), "42 min")
        // The panel keeps the shorter form.
        XCTAssertEqual(MenuBarPresenter.duration(2 * 3600), "2 h")

        let base = F.date(6, 10)
        let onTheHour = Meeting(id: "h", title: "Sync", start: base.addingTimeInterval(2 * 3600), end: base.addingTimeInterval(3 * 3600))
        XCTAssertEqual(status([onTheHour], at: base).text, "Next in 2 h 00 min")
        let running = Meeting(id: "r", title: "Workshop", start: base.addingTimeInterval(-600), end: base.addingTimeInterval(3 * 3600 + 5 * 60))
        XCTAssertEqual(status([running], at: base).text, "3 h 05 min left")
    }
}
