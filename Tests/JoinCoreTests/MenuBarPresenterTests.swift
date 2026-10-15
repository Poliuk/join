import Foundation
import Testing
@testable import JoinCore

struct MenuBarPresenterTests {
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

    /// General's Starting soon preview reads as the menu bar would, for each Shows choice.
    @Test func startingSoonPreviewText() {
        #expect(MenuBarPresenter.startingSoonPreviewText(display: .iconOnly, pill: .default) == nil)
        #expect(MenuBarPresenter.startingSoonPreviewText(display: .time, pill: .default) == "Next in 4 min")
        #expect(MenuBarPresenter.startingSoonPreviewText(display: .titleAndTime, pill: .default) == "Hello, I’m a demo event · in 4 min")
        #expect(MenuBarPresenter.startingSoonPreviewText(display: .time, pill: StartingSoonPill(minutes: 3)) == "Next in 3 min",
                "within the pill's own window")
        #expect(MenuBarPresenter.startingSoonPreviewText(display: .time, pill: StartingSoonPill(minutes: 60)) == "Next in 4 min")
        #expect(MenuBarPresenter.demoEventTitle.count <= MenuBarPresenter.maxTitleLength, "shown whole, like a short title")
    }

    @Test func laterTodayCountsDown() {
        let today = status(at: F.date(6, 10, 45))
        #expect(today.kind == .later)
        #expect(today.text == "Next in 2 h 15 min")
        #expect(today.accessibilityLabel == "Join!: Lunch with Lucía in 2 hours 15 minutes, at 1:00 PM")
    }

    @Test func otherDaysShowTheDayAndTime() {
        let tomorrow = status(at: F.date(5, 21, 30))
        #expect(tomorrow.kind == .later)
        #expect(tomorrow.text == "Tomorrow at 1:00 PM")
        #expect(tomorrow.accessibilityLabel == "Join!: Lunch with Lucía tomorrow at 1:00 PM")

        let laterInTheWeek = status([F.review], at: F.date(5, 21, 30))
        #expect(laterInTheWeek.text == "In 2 days at 9:10 AM")
        #expect(laterInTheWeek.accessibilityLabel == "Join!: Revisión semanal in 2 days, Wednesday at 9:10 AM")
    }

    // Monday 10:00 AM, and the next meeting is next Monday at 9:00: VoiceOver names the date, not just "Monday".
    @Test func aWeekAheadCountsDays() {
        let nextWeek = status([F.nextMonday], at: F.date(5, 10))
        #expect(nextWeek.kind == .later)
        #expect(nextWeek.text == "In 7 days at 9:00 AM")
        #expect(nextWeek.accessibilityLabel == "Join!: Weekly in 7 days, \(F.formatted("EEEEdMMMM", day: 12, locale: F.us)) at 9:00 AM")
        #expect(status([F.nextMonday], at: F.date(5, 10), locale: F.gb).text == "In 7 days at 09:00")

        let sixDaysAhead = status([F.sunday], at: F.date(5, 10))
        #expect(sixDaysAhead.text == "In 6 days at 9:00 AM")
        #expect(sixDaysAhead.accessibilityLabel == "Join!: Brunch in 6 days, Sunday at 9:00 AM")
    }

    @Test func withinTheHourCountsDownInMinutes() {
        let result = status(at: F.date(6, 12, 18))
        #expect(result.kind == .withinHour)
        #expect(result.text == "Next in 42 min")
        #expect(result.accessibilityLabel == "Join!: Lunch with Lucía in 42 minutes")
        #expect(status(at: F.date(6, 12)).text == "Next in 60 min")
        #expect(status(at: F.date(6, 11, 59, 59)).kind == .later)
    }

    // 3:56 PM: Workshop has run since 3:00 and Planning starts at 4:00. Starting soon wins over the meeting in progress.
    @Test func startingSoonIsAnAccentPill() {
        let result = status(at: F.date(6, 15, 56))
        #expect(result.kind == .startingSoon)
        #expect(result.text == "Next in 4 min")
        #expect(result.accessibilityLabel == "Join!: Ana/Luis: Product Planning starts in 4 minutes")
        #expect(status(at: F.date(6, 15, 55)).kind == .startingSoon)
        #expect(status(at: F.date(6, 15, 54, 59)).text == "3 h 36 min left", "a second before the window, the running Workshop shows")
        #expect(status(at: F.date(6, 15, 59, 30)).text == "Next in 1 min")
    }

    @Test func inAMeetingShowsTimeLeftAndADrainingRing() {
        let result = status(at: F.date(6, 16, 20))
        #expect(result.text == "40 min left")
        #expect(result.accessibilityLabel == "Join!: Ana/Luis: Product Planning ends in 40 minutes")
        guard case .inMeeting(let remaining) = result.kind else {
            Issue.record("expected inMeeting, got \(result.kind)")
            return
        }
        #expect(abs(remaining - 2.0 / 3.0) <= 0.0001)

        let long = status([F.workshop], at: F.date(6, 16, 20))
        #expect(long.text == "3 h 10 min left")
    }

    @Test func pausedIsIconOnlyAndWinsOverEverything() {
        let paused = status(at: F.date(6, 15, 56), pause: .until(F.date(6, 16, 56)))
        #expect(paused.kind == .paused)
        #expect(paused.text == nil)
        #expect(paused.accessibilityLabel == "Join!: full-screen alerts paused")
        #expect(status(at: F.date(6, 16, 20), pause: .indefinitely).kind == .paused)
        #expect(status(at: F.date(6, 15, 56), pause: .until(F.date(6, 15, 50))).kind == .startingSoon)
    }

    @Test func nothingUpcomingIsIconOnly() {
        let result = status([], at: F.date(6, 10))
        #expect(result.kind == .idle)
        #expect(result.text == nil)
        #expect(status(at: F.date(9, 10)).kind == .idle)
    }

    // The caller passes only alertable meetings. An out-of-office block passed in (the user opted in) drives the bar like any meeting.
    @Test func outOfOfficeBlocksPassedInDriveTheMenuBar() {
        #expect(status(F.week, at: F.date(6, 12, 28)).kind == .startingSoon)
    }

    @Test func iconOnlyWhenNextEventIsHiddenButKeepsTheState() {
        let soon = status(at: F.date(6, 15, 56), showsNextEvent: false, showsTitles: true)
        #expect(soon.kind == .startingSoon)
        #expect(soon.text == nil)
        #expect(soon.accessibilityLabel == "Join!: Ana/Luis: Product Planning starts in 4 minutes")
        #expect(status(at: F.date(6, 12, 18), showsNextEvent: false).text == nil)
        #expect(status(at: F.date(6, 16, 20), showsNextEvent: false).text == nil)
    }

    @Test func currentMeetingIsTheMostRecentlyStarted() {
        #expect(MenuBarPresenter.currentMeeting(in: F.alertable, now: F.date(6, 16, 20))?.id == "plan")
        #expect(MenuBarPresenter.currentMeeting(in: F.alertable, now: F.date(6, 15, 30))?.id == "val")
        #expect(MenuBarPresenter.currentMeeting(in: F.alertable, now: F.date(6, 20)) == nil)
    }

    @Test func durations() {
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
            #expect(MenuBarPresenter.duration(c.seconds) == c.panel, "\(c.seconds) s")
            #expect(MenuBarPresenter.steadyDuration(c.seconds) == c.menuBar, "\(c.seconds) s")
            #expect(MenuBarPresenter.spokenDuration(c.seconds) == c.spoken, "\(c.seconds) s")
        }
    }

    @Test func remainingFraction() {
        #expect(MenuBarPresenter.remainingFraction(of: F.planning, now: F.date(6, 16)) == 1)
        #expect(abs(MenuBarPresenter.remainingFraction(of: F.planning, now: F.date(6, 16, 30)) - 0.5) <= 0.0001)
        #expect(MenuBarPresenter.remainingFraction(of: F.planning, now: F.date(6, 18)) == 0)
        #expect(abs(MenuBarPresenter.elapsedFraction(of: F.planning, now: F.date(6, 16, 15)) - 0.25) <= 0.0001)
    }

    @Test func pausedMessage() {
        let now = F.date(6, 10, 50)
        func message(_ state: PauseState) -> String? {
            F.squash(MenuBarPresenter.pausedMessage(state, now: now, calendar: F.calendar, locale: F.us))
        }
        #expect(message(.active) == nil)
        #expect(message(.until(F.date(6, 10, 49))) == nil)
        #expect(message(.until(F.date(6, 11, 50))) == "Full-screen alerts paused until 11:50 AM")
        #expect(message(.until(F.date(7, 0))) == "Full-screen alerts paused until tomorrow")
        #expect(message(.indefinitely) == "Full-screen alerts paused")
    }

    @Test func headerDate() {
        func header(_ locale: Locale) -> String? {
            F.squash(MenuBarPresenter.headerDate(F.date(6, 10), calendar: F.calendar, locale: locale))
        }
        // The full weekday, day and month in each locale's order: "Tuesday 6 October", "Tuesday, October 6".
        #expect(header(F.gb) == F.formatted("EEEEdMMMM", day: 6, locale: F.gb))
        #expect(header(F.us) == F.formatted("EEEEdMMMM", day: 6, locale: F.us))
    }

    @Test func titlesPrecedeTheTime() {
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
            #expect(status(c.meetings, at: c.now, showsTitles: true).text == c.expected, "at \(c.now)")
        }
    }

    @Test func menuBarCountdownsKeepTheirWidth() {
        #expect(status(at: F.date(6, 11)).text == "Next in 2 h 00 min")              // Lunch at 1:00 PM
        #expect(status([F.workshop], at: F.date(6, 16, 25)).text == "3 h 05 min left") // ends 7:30 PM
    }

    @Test func theStartingSoonWindowComesFromSettings() {
        // 12:52 PM, the next meeting starts at 1:00 PM: 8 minutes away.
        let now = F.date(6, 12, 52)
        #expect(status(at: now).kind == .withinHour)
        let wider = status(at: now, startingSoonWindow: 10 * 60)
        #expect(wider.kind == .startingSoon)
        #expect(wider.text == "Next in 8 min")
        #expect(status(at: F.date(6, 12, 58), startingSoonWindow: 60).kind == .withinHour, "1 minute: not yet at 2 minutes")
        #expect(status(at: F.date(6, 12, 59), startingSoonWindow: 60).kind == .startingSoon)
    }

    /// `meeting` with your answer set to `status`.
    private func answered(_ meeting: Meeting, _ status: ParticipationStatus) -> Meeting {
        var meeting = meeting
        meeting.myStatus = status
        return meeting
    }

    @Test func aMaybeMeetingInProgressStepsAsideForAnAcceptedOneInsideIt() {
        let maybeWorkshop = answered(F.workshop, .tentative)
        let lateCall = Meeting(id: "late", title: "Late call", start: F.date(6, 18), end: F.date(6, 18, 30))
        let cases: [(meetings: [Meeting], now: Date, focus: [String], why: String)] = [
            ([maybeWorkshop, F.planning], F.date(6, 15, 13), ["plan"], "in progress, with the accepted call inside it within the hour"),
            ([maybeWorkshop, F.planning], F.date(6, 14, 57), ["val", "plan"], "not started yet: it counts, like its alert"),
            ([maybeWorkshop, F.planning], F.date(6, 17, 5), ["val", "plan"], "the call is over: the block counts again"),
            ([maybeWorkshop, lateCall], F.date(6, 15, 13), ["val", "late"], "the accepted call is hours away: the block shows until the hour before"),
            ([answered(F.lunch, .unknown), F.planning], F.date(6, 13, 30), ["lunch", "plan"], "an unanswered meeting that clashes with nothing counts"),
            ([answered(F.review, .tentative), F.thursday], F.date(6, 20), ["rev", "thu"], "a Maybe meeting tomorrow isn't skipped for an accepted one later"),
            ([maybeWorkshop, answered(F.planning, .unknown)], F.date(6, 15, 13), ["val", "plan"], "nothing accepted: everything counts"),
        ]
        for c in cases {
            #expect(MenuBarPresenter.focus(c.meetings, now: c.now).map(\.id) == c.focus, "\(c.why)")
        }
    }

    // A Maybe or unanswered block has run since 3:00 PM; a call you accepted starts at 4:00. The call drives the bar.
    @Test func anAcceptedMeetingOutranksAMaybeBlockInProgress() {
        for answer in [ParticipationStatus.tentative, .unknown] {
            let meetings = [answered(F.workshop, answer), F.planning]
            #expect(status(meetings, at: F.date(6, 15, 13)).text == "Next in 47 min", "\(answer)")
            #expect(status(meetings, at: F.date(6, 16, 20)).text == "40 min left", "\(answer): the call in progress")
            #expect(status(meetings, at: F.date(6, 17, 5)).text == "2 h 25 min left", "\(answer): after the call, the block shows")
        }
    }

    @Test func aMaybeMeetingInsideAnAcceptedOneGetsItsPillButNotTheRing() {
        let meetings = [F.workshop, answered(F.planning, .tentative)]
        #expect(status(meetings, at: F.date(6, 15, 56)).text == "Next in 4 min", "its alert is coming, so the pill shows")
        #expect(status(meetings, at: F.date(6, 16, 20)).text == "3 h 10 min left",
                "in progress, the Maybe call steps aside: the accepted meeting keeps the ring though it started earlier")
        #expect(status([answered(F.planning, .tentative), F.review], at: F.date(6, 15, 13)).text == "Next in 47 min",
                "a Maybe meeting today still comes before an accepted one tomorrow")
        let unansweredLunch = [answered(F.lunch, .unknown), F.planning]
        #expect(status(unansweredLunch, at: F.date(6, 12, 57)).kind == .startingSoon, "no clash: an unanswered meeting keeps its pill")
        #expect(status(unansweredLunch, at: F.date(6, 13, 20)).text == "40 min left", "and its ring")
    }

    // A tentative 8 PM to 2 AM block with an accepted 1 AM check-in: the block keeps the ring until the hour before.
    @Test func aMaybeBlockAcrossMidnightKeepsItsRingUntilTheHourBefore() {
        let hackathon = Meeting(id: "hack", title: "Hackathon", start: F.date(6, 20), end: F.date(7, 2), myStatus: .tentative)
        let checkIn = Meeting(id: "check", title: "Check-in", start: F.date(7, 1), end: F.date(7, 1, 15))
        #expect(status([hackathon, checkIn], at: F.date(6, 21)).text == "5 h 00 min left")
        #expect(status([hackathon, checkIn], at: F.date(7, 0, 10)).text == "Next in 50 min")
    }

    // A dismissed event leaves the alertable meetings (`MeetingFilter.alertable`), so the bar moves on to what comes next.
    @Test func aDismissedMeetingLeavesTheMenuBarToTheNextOne() {
        func alertable(dismissing meetings: [Meeting]) -> [Meeting] {
            let dismissed = meetings.reduce(DismissedEvents()) { $0.dismissing($1) }
            return MeetingFilter.alertable(F.week, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .listOnly, dismissed: dismissed)
        }
        #expect(alertable(dismissing: []) == F.alertable)

        // 12:18 PM: lunch in 42 minutes; dismissed, the Workshop at 3:00 PM is next.
        let afterLunch = status(alertable(dismissing: [F.lunch]), at: F.date(6, 12, 18))
        #expect(afterLunch.kind == .later)
        #expect(afterLunch.text == "Next in 2 h 42 min")
        #expect(afterLunch.accessibilityLabel == "Join!: Workshop in 2 hours 42 minutes, at 3:00 PM")

        // 3:56 PM: Planning starting soon; dismissed, the Workshop in progress takes the bar.
        let running = status(alertable(dismissing: [F.planning]), at: F.date(6, 15, 56))
        #expect(running.text == "3 h 34 min left")
        guard case .inMeeting = running.kind else {
            Issue.record("expected inMeeting, got \(running.kind)")
            return
        }

        // 4:20 PM: in Planning; dismissed, the ring is the Workshop's.
        let workshop = status(alertable(dismissing: [F.planning]), at: F.date(6, 16, 20))
        #expect(workshop.text == "3 h 10 min left")
        #expect(workshop.accessibilityLabel == "Join!: Workshop ends in 3 hours 10 minutes")

        // Dismissing the Workshop too leaves tomorrow's first meeting.
        #expect(status(alertable(dismissing: [F.planning, F.workshop]), at: F.date(6, 16, 20)).text == "Tomorrow at 9:10 AM")
        #expect(status(alertable(dismissing: F.alertable), at: F.date(6, 16, 20)).kind == .idle, "everything dismissed: the icon alone")
    }
}
