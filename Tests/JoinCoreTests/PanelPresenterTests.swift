import Foundation
import Testing
@testable import JoinCore

/// An en_US date as Foundation renders `template` on fixture day `day`, e.g. us("EEEdMMM", 6) is "Tue, Oct 6".
private func us(_ template: String, _ day: Int) -> String {
    MenuBarFixtures.formatted(template, day: day, locale: MenuBarFixtures.us)
}

/// The menu bar panel: its card, its sections and rows, the Today | 7 Days switch, and dismissed events.
struct PanelPresenterTests {
    typealias F = MenuBarFixtures

    /// Which card the hero is, to compare without its content.
    enum HeroKind: Sendable {
        case nothingToday, next, startingSoon, now
    }

    /// `dismissed` were each dismissed on their own (This Event). `alertable` defaults to the meetings that aren't
    /// out-of-office blocks or dismissed, as the store passes them.
    private func content(at now: Date, meetings: [Meeting] = F.week, alertable: [Meeting]? = nil, dismissed: Set<String> = [],
                         startingSoonWindow: TimeInterval = MenuBarPresenter.startingSoonWindow,
                         locale: Locale = F.us) -> PanelContent {
        content(at: now, meetings: meetings, alertable: alertable, dismissals: Dictionary(uniqueKeysWithValues: dismissed.map { ($0, .thisEvent) }),
                startingSoonWindow: startingSoonWindow, locale: locale)
    }

    private func content(at now: Date, meetings: [Meeting] = F.week, alertable: [Meeting]? = nil, dismissals: [Meeting.ID: DismissScope],
                         startingSoonWindow: TimeInterval = MenuBarPresenter.startingSoonWindow,
                         locale: Locale = F.us) -> PanelContent {
        PanelPresenter.content(meetings: meetings, alertable: alertable ?? meetings.filter { !$0.isOutOfOffice && dismissals[$0.id] == nil },
                               dismissed: dismissals, now: now,
                               startingSoonWindow: startingSoonWindow, calendar: F.calendar, locale: locale)
    }

    /// The card's overlap warning: nil when there's none, and on the card of a meeting in progress.
    private func overlap(on card: PanelCard) -> String? {
        if case .upcoming(_, let overlap) = card.detail { overlap } else { nil }
    }

    private func kind(_ hero: PanelHero) -> HeroKind {
        switch hero {
        case .nothingToday: .nothingToday
        case .next: .next
        case .startingSoon: .startingSoon
        case .now: .now
        }
    }

    /// The "No more meetings today" card's line, or nil for another card.
    private func detail(_ content: PanelContent) -> String? {
        guard case .nothingToday(let detail) = content.hero else { return nil }
        return F.squash(detail)
    }

    private func titles(_ sections: [PanelSection]) -> [String] {
        sections.map { [$0.title, F.squash($0.subtitle)].compactMap { $0 }.joined(separator: " / ") }
    }

    private func titles(_ content: PanelContent) -> [String] {
        titles(content.sections)
    }

    private func ids(_ section: PanelSection) -> [String] {
        section.rows.map(\.meeting.id)
    }

    private func row(_ id: String, in content: PanelContent) -> PanelRow? {
        content.sections.lazy.flatMap(\.rows).first { $0.id == id }
    }

    /// `meeting`, answered Maybe.
    static func maybe(_ meeting: Meeting) -> Meeting {
        var meeting = meeting
        meeting.myStatus = .tentative
        return meeting
    }

    // MARK: The artboards

    // Main artboard: Monday 9:30 PM, nothing left today.
    @Test func nothingLeftToday() {
        let result = content(at: F.date(5, 21, 30))
        #expect(detail(result) == "Next up tomorrow at 1:00 PM, in 15 h 30 min")
        #expect(titles(result) == ["Tomorrow / \(us("EEEdMMM", 6))", "Wednesday / \(us("dMMM", 7))", "Thursday / \(us("dMMM", 8))"])
        #expect(result.sections.map(ids) == [["ooo", "lunch", "val", "plan"], ["rev", "one", "road"], ["thu"]])
    }

    /// A locale's day headings and times: each weekday as it's written there, capitalized as a heading where the
    /// locale writes it in lowercase.
    struct LocaleCase: Sendable, CustomTestStringConvertible {
        let locale: Locale
        let wednesday: String
        let thursday: String
        let nineAM: String

        var testDescription: String { locale.identifier }
    }

    // en_GB: day before month and a 24-hour clock, e.g. "Tomorrow / Tue 6 Oct" and "Next up Mon 12 Oct at 09:00".
    // es_ES writes "miércoles": the heading reads "Miércoles". ICU's punctuation (a comma after the weekday on
    // macOS 14) comes from Foundation rather than being pinned.
    @Test(arguments: [
        LocaleCase(locale: F.gb, wednesday: "Wednesday", thursday: "Thursday", nineAM: "09:00"),
        LocaleCase(locale: Locale(identifier: "es_ES"), wednesday: "Miércoles", thursday: "Jueves", nineAM: "9:00"),
    ])
    func datesAndTimesFollowTheLocale(_ locale: LocaleCase) {
        func date(_ template: String, _ day: Int) -> String { F.formatted(template, day: day, locale: locale.locale) }
        #expect(titles(content(at: F.date(5, 21, 30), locale: locale.locale))
                == ["Tomorrow / \(date("EEEdMMM", 6))", "\(locale.wednesday) / \(date("dMMM", 7))", "\(locale.thursday) / \(date("dMMM", 8))"])
        let nextWeek = content(at: F.date(5, 10), meetings: [F.nextMonday], locale: locale.locale)
        #expect(detail(nextWeek) == "Next up \(date("EEEdMMM", 12)) at \(locale.nineAM)", "a week ahead: the date, and the locale's time")
    }

    @Test func rowsFromTheDesign() throws {
        let tuesday = content(at: F.date(5, 21, 30)).sections.first?.rows ?? []
        try #require(tuesday.count == 4, "expected Tuesday's 4 rows, got \(tuesday.map(\.id))")

        let outOfOffice = tuesday[0]
        #expect(outOfOffice.isMuted)
        #expect(outOfOffice.action == nil)
        #expect(outOfOffice.detail == nil)
        #expect(F.squash(outOfOffice.startTime) == "12:30 PM")
        #expect(F.squash(outOfOffice.endTime) == "2:30 PM")

        let lunch = tuesday[1]
        #expect(!lunch.isMuted)
        #expect(lunch.detail == .location("C. de Ruiz de Alarcón, 23 · Retiro"))
        #expect(lunch.action == .directions(LocationFormatter.directionsURL(to: F.lunch.location!)!))

        let workshop = tuesday[2]
        #expect(workshop.detail == nil)
        #expect(workshop.action == .join(F.meet))

        let planning = tuesday[3]
        #expect(planning.detail == .overlap("Overlaps Workshop"))
        #expect(planning.action == .join(F.meet))
    }

    // Later artboard: Tuesday 10:45 AM, the next meeting is later today.
    @Test func nextMeetingLaterToday() {
        let result = content(at: F.date(6, 10, 45))
        guard case .next(let card) = result.hero else {
            Issue.record("expected next, got \(result.hero)")
            return
        }
        #expect(card.meeting.id == "lunch")
        #expect(card.label == "Next · in 2 h 15 min")
        #expect(F.squash(card.timeRange) == "1:00 – 2:00 PM")
        #expect(card.detail == .upcoming(location: "C. de Ruiz de Alarcón, 23 · Retiro", overlap: nil),
                "out-of-office blocks never count as overlaps")
        #expect(card.action == .directions(LocationFormatter.directionsURL(to: F.lunch.location!)!))

        #expect(titles(result) == ["Today", "Tomorrow / \(us("EEEdMMM", 7))", "Thursday / \(us("dMMM", 8))"])
        #expect(result.sections.first.map(ids) == ["ooo", "lunch", "val", "plan"], "Today lists the hero's meeting too")
    }

    // Busy artboard: Tuesday 3:56 PM, a meeting starts in 4 minutes while another one runs.
    @Test func startingSoonWinsOverAMeetingInProgress() {
        let result = content(at: F.date(6, 15, 56))
        guard case .startingSoon(let card) = result.hero else {
            Issue.record("expected startingSoon, got \(result.hero)")
            return
        }
        #expect(card.meeting.id == "plan")
        #expect(card.label == "Starts in 4 min")
        #expect(F.squash(overlap(on: card)) == "Overlaps Workshop, which runs until 7:30 PM")
        #expect(card.action == .join(F.meet))

        #expect(titles(result) == ["Now", "Today", "Tomorrow / \(us("EEEdMMM", 7))", "Thursday / \(us("dMMM", 8))"])
        #expect(result.sections.prefix(2).map(ids) == [["val"], ["plan"]], "the starting-soon meeting is also listed under Today")
        let nowRow = result.sections.first?.rows.first
        guard case .progress(let elapsed, let left) = nowRow?.detail else {
            Issue.record("expected progress, got \(String(describing: nowRow?.detail))")
            return
        }
        #expect(abs(elapsed - 56.0 / 270.0) <= 0.0001)
        #expect(left == "3 h 34 min left")
    }

    // Meeting artboard: Tuesday 4:20 PM, in two meetings at once.
    @Test func inAMeeting() {
        let result = content(at: F.date(6, 16, 20))
        guard case .now(let card) = result.hero else {
            Issue.record("expected now, got \(result.hero)")
            return
        }
        #expect(card.meeting.id == "plan", "the most recently started meeting gets the card")
        #expect(card.label == "Now · 40 min left")
        #expect(F.squash(card.timeRange) == "4:00 – 5:00 PM")
        guard case .ongoing(let progress) = card.detail else {
            Issue.record("expected progress, got \(card.detail)")
            return
        }
        #expect(abs(progress - 1.0 / 3.0) <= 0.0001, "a progress bar, and so no place or overlap")
        #expect(card.action == .join(F.meet))

        #expect(titles(result) == ["Also now", "Tomorrow / \(us("EEEdMMM", 7))", "Thursday / \(us("dMMM", 8))"])
        #expect(result.sections.first.map(ids) == ["val"], "the meeting on the Now card isn't repeated")
        let alsoNow = result.sections.first?.rows.first
        guard case .progress(let elapsed, let left) = alsoNow?.detail else {
            Issue.record("expected progress, got \(String(describing: alsoNow?.detail))")
            return
        }
        #expect(abs(elapsed - 80.0 / 270.0) <= 0.0001)
        #expect(left == "3 h 10 min left")
    }

    // 1:30 PM, at lunch during the out-of-office block: the block runs, but its row has no progress line.
    @Test func nowSectionHoldsAnOngoingOutOfOfficeBlock() throws {
        let result = content(at: F.date(6, 13, 30))
        guard case .now(let card) = result.hero else {
            Issue.record("expected now, got \(result.hero)")
            return
        }
        #expect(card.meeting.id == "lunch")
        #expect(card.action == .directions(LocationFormatter.directionsURL(to: F.lunch.location!)!))
        #expect(titles(result).first == "Also now")
        #expect(result.sections.first.map(ids) == ["ooo"])
        let row = try #require(result.sections.first?.rows.first, "expected an Also now row")
        #expect(row.isMuted)
        #expect(row.detail == nil)
    }

    /// A meeting is on from the minute it starts (on the card, or under Now) until the minute it ends, when it
    /// leaves the panel.
    @Test(arguments: [
        ("Planning at its start takes the card", F.date(6, 16), HeroKind.now, "plan", "Now · 1 h left", ["val"], []),
        ("Planning at its end is gone", F.date(6, 17), .now, "val", "Now · 2 h 30 min left", [], []),
        ("the out-of-office block at its start is under Now", F.date(6, 12, 30), .next, "lunch", "Next · in 30 min",
         ["ooo"], ["lunch", "val", "plan"]),
        ("lunch at its end is gone", F.date(6, 14), .next, "val", "Next · in 1 h", ["ooo"], ["val", "plan"]),
    ] as [(String, Date, HeroKind, String, String, [String], [String])])
    func aMeetingIsOnFromItsStartUntilItsEnd(
        _ name: String, now: Date, hero: HeroKind, card: String, label: String, onNow: [String], laterToday: [String]
    ) {
        let result = content(at: now)
        #expect(kind(result.hero) == hero)
        #expect(result.hero.card?.meeting.id == card)
        #expect(result.hero.card?.label == label)
        let week = result.filtered(by: .week)
        #expect((week.now.map(ids) ?? []) == onNow)
        #expect((week.upcoming.first { $0.title == "Today" }.map(ids) ?? []) == laterToday)
    }

    /// "No more meetings today": a countdown only under 24 h, "tomorrow" by calendar day, the weekday within the
    /// coming week, the date a week or more ahead; dismissed meetings are skipped.
    @Test(arguments: [
        ("tomorrow, 27 h ahead: no countdown", F.date(5, 10), F.week, [], "Next up tomorrow at 1:00 PM"),
        ("exactly 24 h ahead: no countdown", F.date(5, 13), F.week, [], "Next up tomorrow at 1:00 PM"),
        ("a minute under 24 h", F.date(5, 13, 1), F.week, [], "Next up tomorrow at 1:00 PM, in 23 h 59 min"),
        ("lunch dismissed", F.date(5, 21, 30), F.week, ["lunch"], "Next up tomorrow at 3:00 PM, in 17 h 30 min"),
        ("tomorrow's meetings dismissed", F.date(5, 21, 30), F.week, ["lunch", "val", "plan"], "Next up Wednesday at 9:10 AM"),
        ("everything dismissed", F.date(5, 21, 30), F.week, Set(F.alertable.map(\.id)), "Nothing in the next 7 days"),
        ("the weekday within the coming week", F.date(6, 20), [F.thursday], [], "Next up Thursday at 10:00 AM"),
        ("six days ahead", F.date(5, 10), [F.sunday], [], "Next up Sunday at 9:00 AM"),
        ("a week ahead, the date", F.date(5, 10), [F.nextMonday], [], "Next up \(us("EEEdMMM", 12)) at 9:00 AM"),
        ("nothing in the store", F.date(6, 20), [], [], "Nothing in the next 7 days"),
    ] as [(String, Date, [Meeting], Set<String>, String)])
    func nextUpDetail(_ name: String, now: Date, meetings: [Meeting], dismissed: Set<String>, expected: String) {
        #expect(detail(content(at: now, meetings: meetings, dismissed: dismissed)) == expected)
    }

    // The store looks 7 days ahead, so its last day falls on today's weekday. Its heading is the weekday, like
    // any day after tomorrow, and the date beside it tells it from today.
    @Test func theWeeksLastDayIsHeadedByItsWeekdayAndDate() {
        #expect(titles(content(at: F.date(5, 10), meetings: [F.sunday, F.nextMonday]))
                == ["Sunday / \(us("dMMM", 11))", "Monday / \(us("dMMM", 12))"])
    }

    @Test func locationsThatAreNotPlaces() throws {
        let hybrid = Meeting(id: "h", title: "Hybrid", start: F.date(6, 9), end: F.date(6, 10), location: "Sala Retiro; Microsoft Teams Meeting")
        let bareLink = Meeting(id: "l", title: "Link", start: F.date(6, 11), end: F.date(6, 12), location: "meet.google.com/abc-defg-hij")
        let rows = content(at: F.date(5, 21), meetings: [hybrid, bareLink]).sections.first?.rows ?? []
        try #require(rows.count == 2, "expected 2 rows, got \(rows.map(\.id))")

        #expect(rows[0].detail == .location("Sala Retiro"))
        #expect(rows[0].action == .directions(LocationFormatter.directionsURL(to: "Sala Retiro")!))
        #expect(rows[1].detail == nil, "a link is no place")
        #expect(rows[1].action == nil)

        guard case .next(let card) = content(at: F.date(6, 8), meetings: [hybrid, bareLink]).hero else {
            Issue.record("expected next")
            return
        }
        #expect(card.detail == .upcoming(location: "Sala Retiro", overlap: nil))
    }

    /// An out-of-office block set to Show and alert takes the card like any other event (product brief #8), with
    /// its place and its Join or Directions, while its row stays striped and muted, with no button.
    @Test(arguments: [
        ("with a place", Meeting(id: "away", title: "Out of office", start: F.date(6, 12, 30), end: F.date(6, 14, 30),
                                 location: F.lunch.location, isOutOfOffice: true),
         PanelAction.directions(LocationFormatter.directionsURL(to: F.lunch.location!)!), "C. de Ruiz de Alarcón, 23 · Retiro"),
        ("with a link", Meeting(id: "away", title: "Out of office", start: F.date(6, 12, 30), end: F.date(6, 14, 30),
                                joinURL: F.meet, isOutOfOffice: true),
         .join(F.meet), nil),
    ] as [(String, Meeting, PanelAction, String?)])
    func anOutOfOfficeBlockThatAlertsHasAButtonOnItsCardOnly(_ name: String, block: Meeting, action: PanelAction, location: String?) throws {
        let result = content(at: F.date(6, 12, 28), meetings: [block], alertable: [block])
        guard case .startingSoon(let card) = result.hero else {
            Issue.record("expected startingSoon, got \(result.hero)")
            return
        }
        #expect(card.meeting.id == block.id)
        #expect(card.action == action)
        #expect(card.detail == .upcoming(location: location, overlap: nil))

        let row = try #require(row(block.id, in: result))
        #expect(row.isMuted)
        #expect(row.action == nil)
        #expect(row.detail == nil)
        #expect(row.dismissal == .dismissable(asksScope: false))
    }

    static let alpha = Meeting(id: "a", title: "Alpha", start: F.date(6, 9), end: F.date(6, 10))
    static let bravo = Meeting(id: "b", title: "Bravo", start: F.date(6, 9), end: F.date(6, 9, 30))
    static let backToBack = Meeting(id: "f", title: "Next", start: F.date(6, 10), end: F.date(6, 11))
    static let shortEarlier = Meeting(id: "c", title: "Short", start: F.date(6, 8, 30), end: F.date(6, 9, 15))
    static let longEarlier = Meeting(id: "d", title: "Long", start: F.date(6, 8), end: F.date(6, 12))
    static let late = Meeting(id: "e", title: "Late", start: F.date(6, 9, 10), end: F.date(6, 9, 40))

    /// The meeting another one starts in the middle of: only the later of two is flagged, a same-start tie goes
    /// by order, the latest-ending of several is named, back-to-back meetings don't clash, and out-of-office
    /// blocks never count.
    @Test(arguments: [
        ("Planning starts during the Workshop", F.planning, F.week, "val"),
        ("the earlier meeting isn't flagged", F.workshop, F.week, nil),
        ("lunch during the out-of-office block", F.lunch, F.week, nil),
        ("the out-of-office block itself", F.outOfOffice, F.week, nil),
        ("a same-start tie, the first in order", alpha, [alpha, bravo], nil),
        ("a same-start tie, the second", bravo, [alpha, bravo], "a"),
        ("the latest-ending of two running", late, [shortEarlier, longEarlier, late], "d"),
        ("back to back", backToBack, [alpha, backToBack], nil),
    ] as [(String, Meeting, [Meeting], String?)])
    func overlaps(_ name: String, meeting: Meeting, meetings: [Meeting], expected: String?) {
        #expect(PanelPresenter.overlap(for: meeting, in: meetings)?.id == expected)
    }

    // Just before midnight a meeting at 12:03 AM is starting soon; its day's section lists it too.
    @Test func startingSoonAfterMidnightIsListedUnderItsDay() {
        let early = Meeting(id: "early", title: "Early", start: F.date(7, 0, 3), end: F.date(7, 0, 30), joinURL: F.meet)
        let result = content(at: F.date(6, 23, 59), meetings: [early, F.review])
        guard case .startingSoon(let card) = result.hero else {
            Issue.record("expected startingSoon, got \(result.hero)")
            return
        }
        #expect(card.meeting.id == "early")
        #expect(titles(result) == ["Tomorrow / \(us("EEEdMMM", 7))"])
        #expect(result.sections.map(ids) == [["early", "rev"]])
    }

    /// The Events choices reach the panel through the meetings it's given: Exclude leaves the out-of-office block
    /// out of the list, and only Show and alert lets it take the card, two minutes before it starts.
    @Test(arguments: [
        (EventVisibility.listOnly, true, "lunch"),
        (.showAndAlert, true, "ooo"),
        (.exclude, false, "lunch"),
    ])
    func theListAndTheCardFollowTheEventsChoices(outOfOffice: EventVisibility, listsTheBlock: Bool, card: String) {
        func panel(at now: Date) -> PanelContent {
            content(
                at: now,
                meetings: MeetingFilter.visible(F.week, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: outOfOffice),
                alertable: MeetingFilter.alertable(F.week, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: outOfOffice)
            )
        }
        let everything = F.week.map(\.id)
        #expect(panel(at: F.date(5, 21, 30)).sections.flatMap(ids) == (listsTheBlock ? everything : everything.filter { $0 != "ooo" }))
        #expect(panel(at: F.date(6, 12, 28)).hero.card?.meeting.id == card)
    }

    /// The card turns starting-soon at the same moment as the menu bar's pill, for the window set in Settings.
    @Test(arguments: [
        ("8 minutes ahead, the usual window", F.date(6, 12, 52), MenuBarPresenter.startingSoonWindow, false, "Next · in 8 min"),
        ("8 minutes ahead, a 10-minute window", F.date(6, 12, 52), 10 * 60, true, "Starts in 8 min"),
        ("a second before the usual window", F.date(6, 12, 54, 59), MenuBarPresenter.startingSoonWindow, false, "Next · in 6 min"),
        ("the usual window's first second", F.date(6, 12, 55), MenuBarPresenter.startingSoonWindow, true, "Starts in 5 min"),
        ("2 minutes ahead, a 1-minute window", F.date(6, 12, 58), 60, false, "Next · in 2 min"),
        ("1 minute ahead, a 1-minute window", F.date(6, 12, 59), 60, true, "Starts in 1 min"),
    ] as [(String, Date, TimeInterval, Bool, String)])
    func theStartingSoonCardFollowsTheMenuBarPillsWindow(_ name: String, now: Date, window: TimeInterval, isSoon: Bool, label: String) {
        let hero = content(at: now, startingSoonWindow: window).hero
        #expect(kind(hero) == (isSoon ? .startingSoon : .next))
        #expect(hero.card?.meeting.id == "lunch")
        #expect(hero.card?.label == label)
        let pill = MenuBarPresenter.status(meetings: F.alertable, now: now, pauseState: .active, display: .time,
                                           startingSoonWindow: window, calendar: F.calendar, locale: F.us)
        #expect((pill.kind == .startingSoon) == isSoon, "the menu bar's pill turns at the same moment")
    }

    // MARK: Today | 7 Days

    @Test func todayListsTodayAndTheWeekAddsTheFollowingDays() {
        let result = content(at: F.date(6, 10, 45))
        let today = result.filtered(by: .today)
        #expect(today.isShown)
        #expect(today.isTodayAvailable)
        #expect(today.effective == .today)
        #expect(titles(today.sections) == ["Today"])
        #expect(today.sections.flatMap(ids) == ["ooo", "lunch", "val", "plan"])

        let week = result.filtered(by: .week)
        #expect(week.effective == .week)
        #expect(week.sections == result.sections, "7 Days is the whole list")
        #expect(Array(week.sections.prefix(today.sections.count)) == today.sections,
                "switching keeps today's sections first; the week only adds day headings and the days after")
    }

    /// What the Today | 7 Days switch shows with Today chosen: Today is dimmed, and the week shows, when nothing
    /// is left today but out-of-office blocks or the card's own meeting. Dismissed meetings count: they're still on.
    struct TodayAvailability: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let now: Date
        let meetings: [Meeting]
        let dismissed: Set<String>
        let card: String?
        let isAvailable: Bool
        let titles: [String]
        let listed: [String]

        init(_ name: String, at now: Date, _ meetings: [Meeting] = F.week, dismissed: Set<String> = [], card: String? = nil,
             available isAvailable: Bool, _ titles: [String], _ listed: [String]) {
            testDescription = name
            self.now = now
            self.meetings = meetings
            self.dismissed = dismissed
            self.card = card
            self.isAvailable = isAvailable
            self.titles = titles
            self.listed = listed
        }
    }

    static let away = Meeting(id: "away", title: "Out of office", start: F.date(6, 18), end: F.date(6, 23), isOutOfOffice: true)

    static let availability: [TodayAvailability] = [
        // The old app's Today showed an empty list here.
        TodayAvailability("the evening, nothing left today", at: F.date(5, 21, 30), available: false,
                          ["Tomorrow", "Wednesday", "Thursday"], ["ooo", "lunch", "val", "plan", "rev", "one", "road", "thu"]),
        TodayAvailability("during the day's last meeting, which has the card", at: F.date(6, 17, 30), card: "val", available: false,
                          ["Tomorrow", "Thursday"], ["rev", "one", "road", "thu"]),
        // A Today of out-of-office rows only would be an empty list in all but name.
        TodayAvailability("only an out-of-office block left", at: F.date(6, 18, 30), [away, F.review], available: false,
                          ["Now", "Tomorrow"], ["away", "rev"]),
        TodayAvailability("only dismissed meetings left", at: F.date(6, 14, 40), dismissed: ["val", "plan"], available: true,
                          ["Today"], ["val", "plan"]),
        TodayAvailability("the day's last meeting dismissed", at: F.date(6, 17, 30), dismissed: ["val"], available: true,
                          ["Now"], ["val"]),
    ]

    @Test(arguments: availability)
    func todayAvailability(_ expected: TodayAvailability) {
        let result = content(at: expected.now, meetings: expected.meetings, dismissed: expected.dismissed)
        #expect(result.hero.card?.meeting.id == expected.card)
        let state = result.filtered(by: .today)
        #expect(state.isTodayAvailable == expected.isAvailable)
        #expect(state.effective == (expected.isAvailable ? .today : .week), "the stored choice, or the week while Today has nothing")
        #expect(state.sections.map(\.title) == expected.titles)
        #expect(state.sections.flatMap(ids) == expected.listed)
    }

    @Test func theSwitchHidesWhenNothingComesAfterToday() {
        let state = content(at: F.date(6, 10, 45), meetings: [F.lunch, F.workshop]).filtered(by: .week)
        #expect(!state.isShown)
        #expect(state.sections.flatMap(ids) == ["lunch", "val"])
        #expect(!state.showsDayHeadings, "nothing after today: a lone Today heading would say nothing")

        let empty = content(at: F.date(6, 20), meetings: [])
        #expect(empty.sections.isEmpty, "an empty store lists nothing")
        #expect(!empty.filtered(by: .today).isShown)
    }

    // Today: "Now", then "Upcoming events" with today's rows and no day heading. 7 Days: the same "Upcoming
    // events", with each day (Today, Tomorrow, Thursday) as a heading under it, as the user asked.
    @Test func upcomingEventsGroupsTheDaysUnderOneHeading() {
        let result = content(at: F.date(6, 15, 56))
        let today = result.filtered(by: .today)
        #expect(today.now?.title == "Now")
        #expect(today.now.map(ids) == ["val"])
        #expect(today.upcoming.map(\.title) == ["Today"])
        #expect(today.upcoming.flatMap(ids) == ["plan"])
        #expect(!today.showsDayHeadings)

        let week = result.filtered(by: .week)
        #expect(week.now.map(ids) == ["val"])
        #expect(week.upcoming.map(\.title) == ["Today", "Tomorrow", "Thursday"])
        #expect(week.showsDayHeadings)
        #expect(PanelFilterState.upcomingTitle == "Upcoming events")
    }

    /// The card picks the way the menu bar does (`MenuBarPresenter.focus`, whose rules MenuBarPresenterTests
    /// table): the meeting that steps aside is listed under Now, or Also now beside a Now card.
    @Test(arguments: [
        ("a Maybe block in progress: the accepted call is next",
         [maybe(F.workshop), F.planning], F.date(6, 15, 13), HeroKind.next, "plan", "Now", ["val"]),
        ("during the accepted call, the Maybe block is also now",
         [maybe(F.workshop), F.planning], F.date(6, 16, 20), .now, "plan", "Also now", ["val"]),
        ("a Maybe call inside an accepted meeting gets the starting-soon card",
         [F.workshop, maybe(F.planning)], F.date(6, 15, 56), .startingSoon, "plan", "Now", ["val"]),
        ("once it runs, the accepted meeting has the card",
         [F.workshop, maybe(F.planning)], F.date(6, 16, 20), .now, "val", "Also now", ["plan"]),
    ] as [(String, [Meeting], Date, HeroKind, String, String, [String])])
    func theCardPicksLikeTheMenuBar(_ name: String, meetings: [Meeting], now: Date, hero: HeroKind, card: String, section: String, listed: [String]) {
        let result = content(at: now, meetings: meetings)
        #expect(kind(result.hero) == hero)
        #expect(result.hero.card?.meeting.id == card)
        #expect(result.sections.first?.title == section)
        #expect(result.sections.first.map(ids) == listed)
    }

    // MARK: Dismissed events

    /// A moment with meetings dismissed: the card, the first section, and one dismissed meeting's detail line.
    struct Handoff: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let now: Date
        let dismissed: Set<String>
        let hero: HeroKind
        let card: String?
        let label: String?
        let section: String
        let listed: [String]
        let row: String
        let detail: String

        init(_ name: String, at now: Date, dismissed: Set<String>, _ hero: HeroKind, card: String? = nil, _ label: String? = nil,
             under section: String, _ listed: [String], row: String, _ detail: String) {
            testDescription = name
            self.now = now
            self.dismissed = dismissed
            self.hero = hero
            self.card = card
            self.label = label
            self.section = section
            self.listed = listed
            self.row = row
            self.detail = detail
        }
    }

    static let handoffs: [Handoff] = [
        // Later artboard: lunch keeps its place under Today, marked instead of its location.
        Handoff("the next meeting: the one after takes the card", at: F.date(6, 10, 45), dismissed: ["lunch"],
                .next, card: "val", "Next · in 4 h 15 min", under: "Today", ["ooo", "lunch", "val", "plan"], row: "lunch", "Dismissed"),
        // Busy artboard: Planning stays under Today, with no overlap warning.
        Handoff("the starting-soon meeting: the one in progress takes the card", at: F.date(6, 15, 56), dismissed: ["plan"],
                .now, card: "val", "Now · 3 h 34 min left", under: "Today", ["plan"], row: "plan", "Dismissed"),
        // Meeting artboard: the time left as the progress line words it, without the bar.
        Handoff("a meeting in progress beside the card's: under Also now", at: F.date(6, 16, 20), dismissed: ["val"],
                .now, card: "plan", "Now · 40 min left", under: "Also now", ["val"], row: "val", "Dismissed · 3 h 10 min left"),
        Handoff("the card's own meeting: the other one in progress takes it", at: F.date(6, 16, 20), dismissed: ["plan"],
                .now, card: "val", "Now · 3 h 10 min left", under: "Also now", ["plan"], row: "plan", "Dismissed · 40 min left"),
        Handoff("a meeting in progress with a later one on the card: under Now", at: F.date(6, 13, 30), dismissed: ["lunch"],
                .next, card: "val", "Next · in 1 h 30 min", under: "Now", ["ooo", "lunch"], row: "lunch", "Dismissed · 30 min left"),
        Handoff("the day's last meeting: under Now, and no card today", at: F.date(6, 17, 30), dismissed: ["val"],
                .nothingToday, under: "Now", ["val"], row: "val", "Dismissed · 2 h left"),
        Handoff("everything: still listed", at: F.date(5, 21, 30), dismissed: Set(F.alertable.map(\.id)),
                .nothingToday, under: "Tomorrow", ["ooo", "lunch", "val", "plan"], row: "lunch", "Dismissed"),
    ]

    /// A dismissed meeting leaves the card to the next one and is listed until it ends, in its place: marked
    /// "Dismissed" (with its time left once it runs) instead of its location, progress or overlap, offering
    /// Restore, not muted, and keeping its Join or Directions.
    @Test(arguments: handoffs)
    func aDismissedMeetingHandsTheCardOn(_ expected: Handoff) throws {
        let result = content(at: expected.now, dismissed: expected.dismissed)
        #expect(kind(result.hero) == expected.hero)
        #expect(result.hero.card?.meeting.id == expected.card)
        #expect(result.hero.card?.label == expected.label)
        #expect(result.sections.first?.title == expected.section)
        #expect(result.sections.first.map(ids) == expected.listed)

        let dismissed = try #require(row(expected.row, in: result))
        #expect(dismissed.dismissal == .dismissed(asksScope: false))
        #expect(dismissed.detail == .dismissed(expected.detail))
        #expect(!dismissed.isMuted, "muted is for out-of-office blocks")
        // Undismissed, the meeting is listed or has the card, with the same button.
        let undismissed = content(at: expected.now)
        #expect(dismissed.action != nil)
        #expect(dismissed.action == (row(expected.row, in: undismissed)?.action ?? undismissed.hero.card?.action), "joining is still allowed")
    }

    // The store passes alertable meetings without the dismissed ones; any left in are dropped all the same.
    @Test func dismissedMeetingsLeftInAlertableNeverTakeTheCard() {
        let result = content(at: F.date(6, 10, 45), alertable: F.alertable, dismissed: [F.lunch.id])
        #expect(result.hero.card?.meeting.id == "val")
        #expect(row("lunch", in: result)?.dismissal == .dismissed(asksScope: false))
    }

    // Dismiss follows what alerts: a Show and alert meeting offers it, a dismissed one offers Restore, and one
    // that never alerts (Show in the list only, out-of-office blocks by default) offers neither, even with a
    // stored entry from before its choice changed.
    @Test func rowsOfferDismissOnlyForMeetingsThatMayAlert() {
        let focus = Meeting(id: "focus", title: "Focus", start: F.date(6, 10), end: F.date(6, 11), hasParticipants: false)
        let all = F.week + [focus]
        let stored = DismissedEvents().dismissing(F.lunch).dismissing(focus)
        func panel(withoutParticipants: EventVisibility, outOfOffice: EventVisibility = .listOnly) -> PanelContent {
            PanelPresenter.content(
                meetings: MeetingFilter.visible(all, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice),
                alertable: MeetingFilter.alertable(all, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice, dismissed: stored),
                dismissed: MeetingFilter.dismissals(all, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice, dismissed: stored),
                now: F.date(5, 21, 30), calendar: F.calendar, locale: F.us
            )
        }

        let listOnly = panel(withoutParticipants: .listOnly)
        let dismissals = Dictionary(uniqueKeysWithValues: listOnly.sections.flatMap(\.rows).map { ($0.id, $0.dismissal) })
        #expect(dismissals == [
            "ooo": nil, "focus": nil, "lunch": .dismissed(asksScope: false), "val": .dismissable(asksScope: false), "plan": .dismissable(asksScope: false),
            "rev": .dismissable(asksScope: false), "one": .dismissable(asksScope: false), "road": .dismissable(asksScope: false), "thu": .dismissable(asksScope: false),
        ])
        #expect(row("focus", in: listOnly)?.detail == nil, "a list-only event isn't shown as dismissed")
        #expect(row("lunch", in: listOnly)?.detail == .dismissed("Dismissed"))

        let showAndAlert = panel(withoutParticipants: .showAndAlert)
        #expect(row("focus", in: showAndAlert)?.dismissal == .dismissed(asksScope: false), "back to Show and alert, it's dismissed again")
        #expect(row("focus", in: showAndAlert)?.detail == .dismissed("Dismissed"))

        // An out-of-office block set to Show and alert can take the card, so its row offers Dismiss too (and Restore),
        // while staying muted.
        let outOfOffice = panel(withoutParticipants: .listOnly, outOfOffice: .showAndAlert)
        #expect(row("ooo", in: outOfOffice)?.dismissal == .dismissable(asksScope: false))
        #expect(row("ooo", in: outOfOffice)?.isMuted == true)
        #expect(row("ooo", in: outOfOffice)?.action == nil)
        let dismissedBlock = content(at: F.date(5, 21, 30), alertable: F.week, dismissed: [F.outOfOffice.id])
        #expect(row("ooo", in: dismissedBlock)?.dismissal == .dismissed(asksScope: false))
        #expect(row("ooo", in: dismissedBlock)?.detail == .dismissed("Dismissed"))
    }

    // A dismissed meeting clashes with nothing, either way round, on the rows and on the card.
    @Test func overlapsIgnoreDismissedMeetings() {
        #expect(row("plan", in: content(at: F.date(5, 21, 30)))?.detail == .overlap("Overlaps Workshop"))
        #expect(row("plan", in: content(at: F.date(5, 21, 30), dismissed: [F.workshop.id]))?.detail == nil,
                "the dismissed Workshop no longer clashes with Planning")

        // 3:56 PM: Planning's card warns about the Workshop until the Workshop is dismissed.
        let soon = content(at: F.date(6, 15, 56), dismissed: [F.workshop.id])
        guard case .startingSoon(let card) = soon.hero else {
            Issue.record("expected startingSoon, got \(soon.hero)")
            return
        }
        #expect(card.meeting.id == "plan")
        #expect(overlap(on: card) == nil)
        #expect(soon.sections.first?.title == "Now")
        #expect(soon.sections.first.map(ids) == ["val"])
        #expect(row("val", in: soon)?.detail == .dismissed("Dismissed · 3 h 34 min left"))

        // Of two meetings running when a third starts, a dismissed one is skipped and the other one named.
        let meetings = [Self.shortEarlier, Self.longEarlier, Self.late]
        #expect(row("e", in: content(at: F.date(6, 7), meetings: meetings))?.detail == .overlap("Overlaps Long"))
        #expect(row("e", in: content(at: F.date(6, 7), meetings: meetings, dismissed: ["d"]))?.detail == .overlap("Overlaps Short"))
        guard case .next(let lateCard) = content(at: F.date(6, 9), meetings: [Self.longEarlier, Self.late], dismissed: ["d"]).hero else {
            Issue.record("expected the late meeting's card")
            return
        }
        #expect(overlap(on: lateCard) == nil, "the card's line ignores the dismissed meeting too")
    }

    // MARK: Repeating events

    /// The planning call as a repeating event: Tuesday's (the artboards' "plan"), Wednesday's and Thursday's,
    /// all at 4:00 PM, one series.
    static func planning(_ day: Int) -> Meeting {
        Meeting(id: day == 6 ? "plan" : "plan\(day)", title: F.planning.title, start: F.date(day, 16), end: F.date(day, 17),
                joinURL: F.meet, seriesID: "planning")
    }

    /// The panel for `stored` dismissals at 3:56 PM on Tuesday (busy artboard, Planning starting soon), with the
    /// planning call repeating, through the same filters as the store.
    private func content(stored: DismissedEvents) -> PanelContent {
        let meetings = F.week.map { $0.id == "plan" ? Self.planning(6) : $0 } + [Self.planning(7), Self.planning(8)]
        return content(
            at: F.date(6, 15, 56),
            meetings: meetings,
            alertable: MeetingFilter.alertable(meetings, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .listOnly, dismissed: stored),
            dismissals: MeetingFilter.dismissals(meetings, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .listOnly, dismissed: stored)
        )
    }

    /// Stored dismissals of the planning series, and what the panel makes of them: Tuesday's, Wednesday's and
    /// Thursday's rows, the card, and whether Wednesday's still clashes with the roadmap review at the same time.
    struct SeriesDismissal: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let stored: DismissedEvents
        let rows: [PanelRow.Dismissal?]
        let card: String
        let roadClashes: Bool
    }

    static let thisEventWednesday = DismissedEvents().dismissing(planning(7))
    static let fromWednesday = DismissedEvents().dismissing(planning(7), scope: .allFutureEvents)
    static let fromTuesday = DismissedEvents().dismissing(planning(6), scope: .allFutureEvents)

    static let seriesDismissals: [SeriesDismissal] = [
        SeriesDismissal(testDescription: "nothing dismissed: Dismiss asks on the series", stored: DismissedEvents(),
                        rows: [.dismissable(asksScope: true), .dismissable(asksScope: true), .dismissable(asksScope: true)],
                        card: "plan", roadClashes: true),
        // Dismissed on its own (the user's ask), Restore acts at once, though it repeats.
        SeriesDismissal(testDescription: "This Event on Wednesday's", stored: thisEventWednesday,
                        rows: [.dismissable(asksScope: true), .dismissed(asksScope: false), .dismissable(asksScope: true)],
                        card: "plan", roadClashes: false),
        SeriesDismissal(testDescription: "This Event on Tuesday's: the Workshop in progress takes the card", stored: DismissedEvents().dismissing(planning(6)),
                        rows: [.dismissed(asksScope: false), .dismissable(asksScope: true), .dismissable(asksScope: true)],
                        card: "val", roadClashes: true),
        // Dismissed with the series, Restore asks; a dismissed occurrence clashes with nothing.
        SeriesDismissal(testDescription: "All Future Events from Wednesday's", stored: fromWednesday,
                        rows: [.dismissable(asksScope: true), .dismissed(asksScope: true), .dismissed(asksScope: true)],
                        card: "plan", roadClashes: false),
        SeriesDismissal(testDescription: "All Future Events from Tuesday's", stored: fromTuesday,
                        rows: [.dismissed(asksScope: true), .dismissed(asksScope: true), .dismissed(asksScope: true)],
                        card: "val", roadClashes: false),
        // Restored on its own inside the rule, Wednesday's is a plain repeating row again; dismissed again with
        // This Event, the rule covers it once more.
        SeriesDismissal(testDescription: "Restore This Event inside Wednesday's rule", stored: fromWednesday.restoring(planning(7)),
                        rows: [.dismissable(asksScope: true), .dismissable(asksScope: true), .dismissed(asksScope: true)],
                        card: "plan", roadClashes: true),
        SeriesDismissal(testDescription: "then This Event again", stored: fromWednesday.restoring(planning(7)).dismissing(planning(7)),
                        rows: [.dismissable(asksScope: true), .dismissed(asksScope: true), .dismissed(asksScope: true)],
                        card: "plan", roadClashes: false),
        // Restoring part of a series: This Event brings back that one; All Future Events from a later occurrence
        // brings back the rest, while Tuesday's, earlier and still listed, stays dismissed; from the rule's start,
        // everything.
        SeriesDismissal(testDescription: "Restore This Event on Wednesday's, inside Tuesday's rule", stored: fromTuesday.restoring(planning(7)),
                        rows: [.dismissed(asksScope: true), .dismissable(asksScope: true), .dismissed(asksScope: true)],
                        card: "val", roadClashes: true),
        SeriesDismissal(testDescription: "Restore All Future Events from Wednesday's", stored: fromTuesday.restoring(planning(7), scope: .allFutureEvents),
                        rows: [.dismissed(asksScope: true), .dismissable(asksScope: true), .dismissable(asksScope: true)],
                        card: "val", roadClashes: true),
        SeriesDismissal(testDescription: "Restore All Future Events from the rule's start", stored: fromTuesday.restoring(planning(6), scope: .allFutureEvents),
                        rows: [.dismissable(asksScope: true), .dismissable(asksScope: true), .dismissable(asksScope: true)],
                        card: "plan", roadClashes: true),
    ]

    /// Whether a button asks This Event or All Future Events: Dismiss on any repeating event, the card's too;
    /// Restore only on an occurrence dismissed with its series; a one-off never asks.
    @Test(arguments: seriesDismissals)
    func repeatingEventDismissals(_ expected: SeriesDismissal) throws {
        let result = content(stored: expected.stored)
        let rows = try ["plan", "plan7", "plan8"].map { id in try #require(row(id, in: result), "\(id)'s row") }
        #expect(rows.map(\.dismissal) == expected.rows)
        for row in rows where row.dismissal?.isDismissed == true {
            #expect(row.detail == .dismissed("Dismissed"), "\(row.id)")
        }
        #expect(result.sections.flatMap(\.rows).filter { !$0.meeting.isRepeating }.allSatisfy { $0.dismissal == .dismissable(asksScope: false) },
                "a one-off never asks")

        let card = try #require(result.hero.card)
        #expect(card.meeting.id == expected.card)
        // The card's Dismiss has no row: it asks by the same rule, for the planning call and not the Workshop.
        #expect(PanelRow.Dismissal.dismissable(for: card.meeting) == .dismissable(asksScope: expected.card == "plan"))
        #expect(row("road", in: result)?.detail == (expected.roadClashes ? .overlap("Overlaps Ana/Luis: Product Planning") : nil))
    }

    // MARK: Copy

    /// Text the user sees, beside what it must say: one string or a list, in order.
    struct Copy: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let actual: [String]
        let expected: [String]

        init(_ name: String, _ actual: [String], _ expected: [String]) {
            testDescription = name
            self.actual = actual
            self.expected = expected
        }

        init(_ name: String, _ actual: String, _ expected: String) {
            self.init(name, [actual], [expected])
        }
    }

    static let copy: [Copy] = [
        Copy("Dismiss", DismissCopy.dismissTitle, "Dismiss"),
        Copy("Restore", DismissCopy.restoreTitle, "Restore"),
        Copy("Dismissed", DismissCopy.dismissedTitle, "Dismissed"),
        Copy("a dismissed row yet to start", DismissCopy.dismissedDetail(left: nil), "Dismissed"),
        Copy("a dismissed row in progress", DismissCopy.dismissedDetail(left: "34 min left"), "Dismissed · 34 min left"),
        Copy("Dismiss's label", DismissCopy.dismissAccessibilityLabel(for: F.workshop, asksScope: false), "Dismiss Workshop"),
        Copy("Dismiss's label on a repeating event", DismissCopy.dismissAccessibilityLabel(for: planning(6), asksScope: true),
             "Dismiss Ana/Luis: Product Planning, opens a menu"),
        Copy("Restore's label", DismissCopy.restoreAccessibilityLabel(for: F.workshop, asksScope: false), "Restore Workshop"),
        Copy("Restore's label, dismissed with its series", DismissCopy.restoreAccessibilityLabel(for: planning(6), asksScope: true),
             "Restore Ana/Luis: Product Planning, opens a menu"),
        Copy("Restore's label, an occurrence dismissed on its own", DismissCopy.restoreAccessibilityLabel(for: planning(6), asksScope: false),
             "Restore Ana/Luis: Product Planning"),
        Copy("a row's Dismiss help", DismissCopy.rowDismissHelp(asksScope: false),
             "Dismiss: no alerts, and it leaves the menu bar and the top card. It stays in this list until it ends."),
        Copy("the card's Dismiss help", DismissCopy.cardDismissHelp(asksScope: false),
             "Dismiss: no alerts, and it leaves the menu bar and this card. It stays in the list until it ends."),
        Copy("Restore's help", DismissCopy.restoreHelp(asksScope: false), "Restore: its alerts and the menu bar come back."),
        Copy("a row's Dismiss help on a repeating event", DismissCopy.rowDismissHelp(asksScope: true),
             "Dismiss: no alerts, and it leaves the menu bar and the top card. It stays in this list until it ends. It repeats: the menu offers this event or all future events."),
        Copy("the card's Dismiss help on a repeating event", DismissCopy.cardDismissHelp(asksScope: true),
             "Dismiss: no alerts, and it leaves the menu bar and this card. It stays in the list until it ends. It repeats: the menu offers this event or all future events."),
        Copy("Restore's help, dismissed with its series", DismissCopy.restoreHelp(asksScope: true),
             "Restore: its alerts and the menu bar come back. It repeats: the menu offers this event or all future events."),
        // Worded like macOS Calendar's question; both menus list the scopes in `allCases` order.
        Copy("the Dismiss menu", DismissScope.allCases.map(DismissCopy.dismissChoice), ["Dismiss This Event", "Dismiss All Future Events"]),
        Copy("the Restore menu", DismissScope.allCases.map(DismissCopy.restoreChoice), ["Restore This Event", "Restore All Future Events"]),
    ]

    @Test(arguments: copy)
    func dismissCopy(_ copy: Copy) {
        #expect(copy.actual == copy.expected)
    }
}
