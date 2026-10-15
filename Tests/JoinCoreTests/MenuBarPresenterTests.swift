import Foundation
import Testing
@testable import JoinCore

/// The menu bar item: what it shows in each state, which meeting drives it, and the shared wording.
struct MenuBarPresenterTests {
    typealias F = MenuBarFixtures

    static func status(
        _ meetings: [Meeting],
        at now: Date,
        pause: PauseState = .active,
        display: MenuBarDisplay = .time,
        startingSoonWindow: TimeInterval = MenuBarPresenter.startingSoonWindow,
        locale: Locale = F.us
    ) -> MenuBarStatus {
        var status = MenuBarPresenter.status(
            meetings: meetings, now: now, pauseState: pause, display: display,
            startingSoonWindow: startingSoonWindow,
            calendar: F.calendar, locale: locale
        )
        status.text = F.squash(status.text)
        status.accessibilityLabel = F.squash(status.accessibilityLabel) ?? ""
        return status
    }

    /// `meeting` with your answer set to `status`.
    static func answered(_ meeting: Meeting, _ status: ParticipationStatus) -> Meeting {
        var meeting = meeting
        meeting.myStatus = status
        return meeting
    }

    // MARK: Status

    /// A moment in the artboards' week, and what the item shows then: its kind, its text and its VoiceOver label.
    struct Status: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let meetings: [Meeting]
        let now: Date
        let pause: PauseState
        let display: MenuBarDisplay
        let window: TimeInterval
        let locale: Locale
        let expected: MenuBarStatus

        init(
            _ name: String,
            _ meetings: [Meeting] = F.alertable,
            at now: Date,
            pause: PauseState = .active,
            display: MenuBarDisplay = .time,
            window: TimeInterval = MenuBarPresenter.startingSoonWindow,
            locale: Locale = F.us,
            _ kind: MenuBarStatus.Kind,
            _ text: String?,
            _ label: String
        ) {
            testDescription = name
            self.meetings = meetings
            self.now = now
            self.pause = pause
            self.display = display
            self.window = window
            self.locale = locale
            expected = MenuBarStatus(kind: kind, text: text, accessibilityLabel: label)
        }
    }

    static let earlyCall = Meeting(id: "early", title: "Early call", start: F.date(6, 1), end: F.date(6, 1, 30))

    static let statuses: [Status] = [
        // Later: a countdown today, then the day and time.
        Status("later today counts down", at: F.date(6, 10, 45),
               .later, "Next in 2 h 15 min", "Join!: Lunch with Lucía in 2 hours 15 minutes, at 1:00 PM"),
        Status("later today keeps its width", at: F.date(6, 11),
               .later, "Next in 2 h 00 min", "Join!: Lunch with Lucía in 2 hours, at 1:00 PM"),
        Status("a second past the hour is later", at: F.date(6, 11, 59, 59),
               .later, "Next in 1 h 01 min", "Join!: Lunch with Lucía in 1 hour 1 minute, at 1:00 PM"),
        Status("tomorrow", at: F.date(5, 21, 30),
               .later, "Tomorrow at 1:00 PM", "Join!: Lunch with Lucía tomorrow at 1:00 PM"),
        // Days are calendar days: two hours ahead, after midnight, is tomorrow, not a countdown.
        Status("tomorrow, two hours ahead", [earlyCall], at: F.date(5, 23),
               .later, "Tomorrow at 1:00 AM", "Join!: Early call tomorrow at 1:00 AM"),
        Status("in 2 days", [F.review], at: F.date(5, 21, 30),
               .later, "In 2 days at 9:10 AM", "Join!: Revisión semanal in 2 days, Wednesday at 9:10 AM"),
        Status("in 6 days, VoiceOver names the weekday", [F.sunday], at: F.date(5, 10),
               .later, "In 6 days at 9:00 AM", "Join!: Brunch in 6 days, Sunday at 9:00 AM"),
        // A week ahead, a bare weekday would sound like today: VoiceOver reads the date.
        Status("in 7 days, VoiceOver reads the date", [F.nextMonday], at: F.date(5, 10),
               .later, "In 7 days at 9:00 AM", "Join!: Weekly in 7 days, \(F.formatted("EEEEdMMMM", day: 12, locale: F.us)) at 9:00 AM"),
        Status("in 7 days, en_GB", [F.nextMonday], at: F.date(5, 10), locale: F.gb,
               .later, "In 7 days at 09:00", "Join!: Weekly in 7 days, \(F.formatted("EEEEdMMMM", day: 12, locale: F.gb)) at 09:00"),
        // A dismissed meeting leaves the alertable meetings, so the item moves on to the next one.
        Status("lunch dismissed, the Workshop is next",
               MeetingFilter.alertable(F.week, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .listOnly,
                                       dismissed: DismissedEvents().dismissing(F.lunch)),
               at: F.date(6, 12, 18),
               .later, "Next in 2 h 42 min", "Join!: Workshop in 2 hours 42 minutes, at 3:00 PM"),

        // Within the hour: minutes only, up to 60, never "1 h".
        Status("within the hour", at: F.date(6, 12, 18),
               .withinHour, "Next in 42 min", "Join!: Lunch with Lucía in 42 minutes"),
        Status("an hour ahead", at: F.date(6, 12),
               .withinHour, "Next in 60 min", "Join!: Lunch with Lucía in 1 hour"),

        // Starting soon: the pill, from the window's start, over a meeting in progress.
        Status("starting soon beats the meeting in progress", at: F.date(6, 15, 56),
               .startingSoon, "Next in 4 min", "Join!: Ana/Luis: Product Planning starts in 4 minutes"),
        Status("starting soon from 5 minutes before", at: F.date(6, 15, 55),
               .startingSoon, "Next in 5 min", "Join!: Ana/Luis: Product Planning starts in 5 minutes"),
        Status("30 seconds before reads 1 min", at: F.date(6, 15, 59, 30),
               .startingSoon, "Next in 1 min", "Join!: Ana/Luis: Product Planning starts in 1 minute"),
        Status("a second before the window, the meeting in progress", at: F.date(6, 15, 54, 59),
               .inMeeting(remaining: 12_901.0 / 16_200.0), "3 h 36 min left", "Join!: Workshop ends in 3 hours 36 minutes"),
        // The caller passes only alertable meetings: an out-of-office block passed in (the user opted in) counts.
        Status("an out-of-office block passed in", F.week, at: F.date(6, 12, 28),
               .startingSoon, "Next in 2 min", "Join!: Out of office starts in 2 minutes"),
        // The window comes from Settings › General › Starting soon.
        Status("8 minutes ahead, the usual window", at: F.date(6, 12, 52),
               .withinHour, "Next in 8 min", "Join!: Lunch with Lucía in 8 minutes"),
        Status("8 minutes ahead, a 10-minute window", at: F.date(6, 12, 52), window: 10 * 60,
               .startingSoon, "Next in 8 min", "Join!: Lunch with Lucía starts in 8 minutes"),
        Status("2 minutes ahead, a 1-minute window", at: F.date(6, 12, 58), window: 60,
               .withinHour, "Next in 2 min", "Join!: Lunch with Lucía in 2 minutes"),
        Status("1 minute ahead, a 1-minute window", at: F.date(6, 12, 59), window: 60,
               .startingSoon, "Next in 1 min", "Join!: Lunch with Lucía starts in 1 minute"),

        // In a meeting: the time left and a ring that drains; the most recently started meeting has it.
        Status("in a meeting", at: F.date(6, 16, 20),
               .inMeeting(remaining: 2.0 / 3.0), "40 min left", "Join!: Ana/Luis: Product Planning ends in 40 minutes"),
        Status("the time left keeps its width", [F.workshop], at: F.date(6, 16, 25),
               .inMeeting(remaining: 185.0 / 270.0), "3 h 05 min left", "Join!: Workshop ends in 3 hours 5 minutes"),
        // A meeting is on from the minute it starts until the minute it ends, exclusive.
        Status("a meeting is on at its start", at: F.date(6, 16),
               .inMeeting(remaining: 1), "1 h 00 min left", "Join!: Ana/Luis: Product Planning ends in 1 hour"),
        Status("and over at its end", at: F.date(6, 17),
               .inMeeting(remaining: 150.0 / 270.0), "2 h 30 min left", "Join!: Workshop ends in 2 hours 30 minutes"),
        Status("the last one over at its end", [F.workshop], at: F.date(6, 19, 30),
               .idle, nil, "Join!: no upcoming meetings"),

        // Nothing upcoming: the icon alone.
        Status("nothing at all", [], at: F.date(6, 10),
               .idle, nil, "Join!: no upcoming meetings"),
        Status("after the week's last meeting", at: F.date(9, 10),
               .idle, nil, "Join!: no upcoming meetings"),

        // Paused: the crossed-out bell over everything, until the pause ends.
        Status("paused over the pill", at: F.date(6, 15, 56), pause: .until(F.date(6, 16, 56)),
               .paused, nil, "Join!: full-screen alerts paused"),
        Status("paused over the ring", at: F.date(6, 16, 20), pause: .indefinitely,
               .paused, nil, "Join!: full-screen alerts paused"),
        Status("a pause that has ended", at: F.date(6, 15, 56), pause: .until(F.date(6, 15, 50)),
               .startingSoon, "Next in 4 min", "Join!: Ana/Luis: Product Planning starts in 4 minutes"),

        // Icon only: no text, but the state and the label stay.
        Status("icon only, starting soon", at: F.date(6, 15, 56), display: .iconOnly,
               .startingSoon, nil, "Join!: Ana/Luis: Product Planning starts in 4 minutes"),
        Status("icon only, within the hour", at: F.date(6, 12, 18), display: .iconOnly,
               .withinHour, nil, "Join!: Lunch with Lucía in 42 minutes"),
        Status("icon only, in a meeting", at: F.date(6, 16, 20), display: .iconOnly,
               .inMeeting(remaining: 2.0 / 3.0), nil, "Join!: Ana/Luis: Product Planning ends in 40 minutes"),
    ]

    /// Precedence: paused, starting soon, in a meeting, within the hour, later.
    @Test(arguments: statuses)
    func menuBarStatus(_ row: Status) {
        let status = Self.status(row.meetings, at: row.now, pause: row.pause, display: row.display,
                                 startingSoonWindow: row.window, locale: row.locale)
        #expect(status == row.expected)
    }

    /// The item follows the meetings you attend (`focus`): a Maybe or unanswered block in progress steps aside
    /// for a call you accepted inside it, while a Maybe call inside an accepted meeting keeps only its pill.
    @Test(arguments: [
        ("the accepted call, not the Maybe block in progress", [answered(F.workshop, .tentative), F.planning], F.date(6, 15, 13),
         MenuBarStatus.Kind.withinHour, "Next in 47 min"),
        ("a Maybe call inside an accepted meeting gets its pill", [F.workshop, answered(F.planning, .tentative)], F.date(6, 15, 56),
         .startingSoon, "Next in 4 min"),
        ("but the accepted meeting keeps the ring", [F.workshop, answered(F.planning, .tentative)], F.date(6, 16, 20),
         .inMeeting(remaining: 190.0 / 270.0), "3 h 10 min left"),
    ] as [(String, [Meeting], Date, MenuBarStatus.Kind, String)])
    func menuBarFollowsTheMeetingsYouAttend(_ name: String, meetings: [Meeting], now: Date, kind: MenuBarStatus.Kind, text: String) {
        let status = Self.status(meetings, at: now)
        #expect(status.kind == kind)
        #expect(status.text == text)
    }

    /// The meetings the menu bar and the panel's card choose from: a Maybe or unanswered meeting in progress
    /// steps aside while an accepted one overlapping it is on or starts within the hour.
    @Test(arguments: [
        ("a Maybe block in progress, with the accepted call inside it within the hour",
         [answered(F.workshop, .tentative), F.planning], F.date(6, 15, 13), ["plan"]),
        ("an unanswered block in progress steps aside too",
         [answered(F.workshop, .unknown), F.planning], F.date(6, 15, 13), ["plan"]),
        ("a Maybe block not started yet counts, like its alert",
         [answered(F.workshop, .tentative), F.planning], F.date(6, 14, 57), ["val", "plan"]),
        ("the call is over: the block counts again",
         [answered(F.workshop, .tentative), F.planning], F.date(6, 17, 5), ["val", "plan"]),
        ("the accepted call is hours away: the block counts until the hour before",
         [answered(F.workshop, .tentative), Meeting(id: "late", title: "Late call", start: F.date(6, 18), end: F.date(6, 18, 30))],
         F.date(6, 15, 13), ["val", "late"]),
        ("a Maybe call inside an accepted meeting counts until it starts",
         [F.workshop, answered(F.planning, .tentative)], F.date(6, 15, 56), ["val", "plan"]),
        ("a Maybe call in progress inside an accepted meeting steps aside",
         [F.workshop, answered(F.planning, .tentative)], F.date(6, 16, 20), ["val"]),
        ("an unanswered meeting that clashes with nothing counts",
         [answered(F.lunch, .unknown), F.planning], F.date(6, 13, 30), ["lunch", "plan"]),
        ("a Maybe meeting tomorrow isn't skipped for an accepted one later",
         [answered(F.review, .tentative), F.thursday], F.date(6, 20), ["rev", "thu"]),
        ("nothing accepted: everything counts",
         [answered(F.workshop, .tentative), answered(F.planning, .unknown)], F.date(6, 15, 13), ["val", "plan"]),
    ] as [(String, [Meeting], Date, [String])])
    func focus(_ name: String, meetings: [Meeting], now: Date, expected: [String]) {
        #expect(MenuBarPresenter.focus(meetings, now: now).map(\.id) == expected)
    }

    /// Two meetings at the same start, in either order: the next one is the first by title, then by id; of two
    /// in progress that started together, the one ending first, then by title and id. The panel's card agrees.
    @Test(arguments: [
        ("next, by title", F.date(6, 9), "b", [
            Meeting(id: "a", title: "Bravo", start: F.date(6, 10), end: F.date(6, 11)),
            Meeting(id: "b", title: "Alpha", start: F.date(6, 10), end: F.date(6, 11)),
        ]),
        ("next, by id", F.date(6, 9), "x", [
            Meeting(id: "y", title: "Sync", start: F.date(6, 10), end: F.date(6, 11)),
            Meeting(id: "x", title: "Sync", start: F.date(6, 10), end: F.date(6, 11)),
        ]),
        ("in progress, the one ending first", F.date(6, 10, 15), "b", [
            Meeting(id: "a", title: "Alpha", start: F.date(6, 10), end: F.date(6, 11)),
            Meeting(id: "b", title: "Bravo", start: F.date(6, 10), end: F.date(6, 10, 30)),
        ]),
        ("in progress, by title", F.date(6, 10, 15), "b", [
            Meeting(id: "a", title: "Bravo", start: F.date(6, 10), end: F.date(6, 11)),
            Meeting(id: "b", title: "Alpha", start: F.date(6, 10), end: F.date(6, 11)),
        ]),
        ("in progress, by id", F.date(6, 10, 15), "x", [
            Meeting(id: "y", title: "Sync", start: F.date(6, 10), end: F.date(6, 11)),
            Meeting(id: "x", title: "Sync", start: F.date(6, 10), end: F.date(6, 11)),
        ]),
    ] as [(String, Date, String, [Meeting])])
    func meetingsStartingTogether(_ name: String, now: Date, expected: String, meetings: [Meeting]) {
        for order in [meetings, Array(meetings.reversed())] {
            let picked = MenuBarPresenter.nextMeeting(in: order, now: now) ?? MenuBarPresenter.currentMeeting(in: order, now: now)
            #expect(picked?.id == expected)
            let card = PanelPresenter.content(meetings: order, alertable: order, now: now, calendar: F.calendar, locale: F.us).hero.card
            #expect(card?.meeting.id == expected, "the panel's card")
        }
    }

    // MARK: Wording

    /// Panel `duration`, menu bar `steadyDuration` (keeps its width past an hour), VoiceOver `spokenDuration`;
    /// all round up, so a countdown never reads "0 min".
    @Test(arguments: [
        (1, "1 min", "1 min", "1 minute"),
        (239.5, "4 min", "4 min", "4 minutes"),
        (42 * 60, "42 min", "42 min", "42 minutes"),
        // Floating-point noise on a whole minute doesn't round up a minute early.
        (42 * 60 + 0.01, "42 min", "42 min", "42 minutes"),
        (65 * 60, "1 h 5 min", "1 h 05 min", "1 hour 5 minutes"),
        (120 * 60, "2 h", "2 h 00 min", "2 hours"),
        (135 * 60, "2 h 15 min", "2 h 15 min", "2 hours 15 minutes"),
        (11 * 3600 + 50 * 60, "11 h 50 min", "11 h 50 min", "11 hours 50 minutes"),
    ] as [(TimeInterval, String, String, String)])
    func durations(seconds: TimeInterval, panel: String, menuBar: String, spoken: String) {
        #expect(MenuBarPresenter.duration(seconds) == panel)
        #expect(MenuBarPresenter.steadyDuration(seconds) == menuBar)
        #expect(MenuBarPresenter.spokenDuration(seconds) == spoken)
    }

    /// At 10:50 AM: a pause that ends at midnight reads "until tomorrow", one that has ended reads nothing.
    @Test(arguments: [
        (PauseState.active, nil),
        (.until(F.date(6, 10, 49)), nil),
        (.until(F.date(6, 11, 50)), "Full-screen alerts paused until 11:50 AM"),
        (.until(F.date(7, 0)), "Full-screen alerts paused until tomorrow"),
        (.indefinitely, "Full-screen alerts paused"),
    ] as [(PauseState, String?)])
    func pausedMessage(_ state: PauseState, expected: String?) {
        #expect(F.squash(MenuBarPresenter.pausedMessage(state, now: F.date(6, 10, 50), calendar: F.calendar, locale: F.us)) == expected)
    }

    /// Title and time: the title first, cut at 24 characters, then the time as the other states word it.
    @Test(arguments: [
        ("within the hour", F.alertable, F.date(6, 12, 18), "Lunch with Lucía · in 42 min"),
        ("later today", F.alertable, F.date(6, 10, 45), "Lunch with Lucía · in 2 h 15 min"),
        ("tomorrow", F.alertable, F.date(5, 21, 30), "Lunch with Lucía · Tomorrow at 1:00 PM"),
        ("27 h ahead: days are calendar days", F.alertable, F.date(5, 10), "Lunch with Lucía · Tomorrow at 1:00 PM"),
        ("in 2 days", [F.review], F.date(5, 21, 30), "Revisión semanal · In 2 days at 9:10 AM"),
        ("73 h ahead, still 3 days", [F.thursday], F.date(5, 9), "Design Crit · In 3 days at 10:00 AM"),
        ("in a meeting, the title cut at 24", F.alertable, F.date(6, 16, 20), "Ana/Luis: Product Plann… · 40 min left"),
    ] as [(String, [Meeting], Date, String)])
    func titlesPrecedeTheTime(_ name: String, meetings: [Meeting], now: Date, expected: String) {
        #expect(Self.status(meetings, at: now, display: .titleAndTime).text == expected)
    }

    /// General's Starting soon preview reads as the menu bar would, for each Shows choice: the demo event in 4
    /// minutes, or sooner when the pill appears later than that.
    @Test(arguments: [
        (MenuBarDisplay.iconOnly, 5, nil),
        (.time, 5, "Next in 4 min"),
        (.titleAndTime, 5, "Hello, I’m a demo event · in 4 min"),
        (.time, 3, "Next in 3 min"),
        (.time, 60, "Next in 4 min"),
    ] as [(MenuBarDisplay, Int, String?)])
    func startingSoonPreviewText(display: MenuBarDisplay, pillMinutes: Int, expected: String?) {
        #expect(MenuBarPresenter.startingSoonPreviewText(display: display, pill: StartingSoonPill(minutes: pillMinutes)) == expected)
    }
}
