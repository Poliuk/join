import Foundation
import Testing
@testable import JoinCore

struct PanelPresenterTests {
    typealias F = MenuBarFixtures

    /// `alertable` defaults to the meetings that aren't out-of-office blocks or `dismissed`, as the store passes them.
    private func content(at now: Date, meetings: [Meeting] = F.week, alertable: [Meeting]? = nil, dismissed: Set<String> = [],
                         dismissedBySeries: Set<String> = [],
                         startingSoonWindow: TimeInterval = MenuBarPresenter.startingSoonWindow,
                         locale: Locale = F.us) -> PanelContent {
        PanelPresenter.content(meetings: meetings, alertable: alertable ?? meetings.filter { !$0.isOutOfOffice && !dismissed.contains($0.id) },
                               dismissed: dismissed, dismissedBySeries: dismissedBySeries, now: now,
                               startingSoonWindow: startingSoonWindow, calendar: F.calendar, locale: locale)
    }

    private func titles(_ content: PanelContent) -> [String] {
        content.sections.map { [$0.title, F.squash($0.subtitle)].compactMap { $0 }.joined(separator: " / ") }
    }

    private func ids(_ section: PanelSection) -> [String] {
        section.rows.map(\.meeting.id)
    }

    /// An en_US date as Foundation renders `template` on fixture day `day`, e.g. us("EEEdMMM", 6) is "Tue, Oct 6".
    private func us(_ template: String, _ day: Int) -> String {
        F.formatted(template, day: day, locale: F.us)
    }

    // Main artboard: Monday 9:30 PM, nothing left today.
    @Test func nothingLeftToday() {
        let result = content(at: F.date(5, 21, 30))
        guard case .nothingToday(let detail) = result.hero else {
            Issue.record("expected nothingToday, got \(result.hero)")
            return
        }
        #expect(F.squash(detail) == "Next up tomorrow at 1:00 PM, in 15 h 30 min")
        #expect(titles(result) == ["Tomorrow / \(us("EEEdMMM", 6))", "Wednesday / \(us("dMMM", 7))", "Thursday / \(us("dMMM", 8))"])
        #expect(result.sections.map(ids) == [["ooo", "lunch", "val", "plan"], ["rev", "one", "road"], ["thu"]])
    }

    // en_GB: day before month and a 24-hour clock, e.g. "Tomorrow / Tue 6 Oct" and "Next up Mon 12 Oct at 09:00".
    // ICU's punctuation (a comma after the weekday on macOS 14) comes from Foundation rather than being pinned.
    @Test func datesAndTimesFollowTheLocale() {
        func gb(_ template: String, _ day: Int) -> String { F.formatted(template, day: day, locale: F.gb) }
        #expect(titles(content(at: F.date(5, 21, 30), locale: F.gb))
                == ["Tomorrow / \(gb("EEEdMMM", 6))", "Wednesday / \(gb("dMMM", 7))", "Thursday / \(gb("dMMM", 8))"])
        let nextWeek = content(at: F.date(5, 10), meetings: [F.nextMonday], locale: F.gb)
        guard case .nothingToday(let detail) = nextWeek.hero else {
            Issue.record("expected nothingToday, got \(nextWeek.hero)")
            return
        }
        #expect(F.squash(detail) == "Next up \(gb("EEEdMMM", 12)) at 09:00", "a week ahead: the date, and a 24-hour time")
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
        #expect(card.location == "C. de Ruiz de Alarcón, 23 · Retiro")
        #expect(card.overlap == nil, "out-of-office blocks never count as overlaps")
        #expect(card.progress == nil)
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
        #expect(F.squash(card.overlap) == "Overlaps Workshop, which runs until 7:30 PM")
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
        #expect(abs((card.progress ?? -1) - 1.0 / 3.0) <= 0.0001)
        #expect(card.overlap == nil)
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

        let afterLunch = content(at: F.date(6, 14, 10))
        guard case .next = afterLunch.hero else {
            Issue.record("expected next, got \(afterLunch.hero)")
            return
        }
        #expect(titles(afterLunch).prefix(2) == ["Now", "Today"])
    }

    // "No more meetings today": a countdown only within 24 h (see nothingLeftToday), the weekday within
    // the coming week, the date a week or more ahead.
    @Test func nextUpDetail() {
        let cases: [(now: Date, meetings: [Meeting], expected: String)] = [
            (F.date(6, 20), [F.thursday], "Next up Thursday at 10:00 AM"),
            (F.date(5, 10), [F.sunday], "Next up Sunday at 9:00 AM"),
            (F.date(5, 10), [F.nextMonday], "Next up \(us("EEEdMMM", 12)) at 9:00 AM"),
            (F.date(6, 20), [], "Nothing in the next 7 days"),
        ]
        for (now, meetings, expected) in cases {
            let result = content(at: now, meetings: meetings)
            guard case .nothingToday(let detail) = result.hero else {
                Issue.record("expected nothingToday for \(expected), got \(result.hero)")
                continue
            }
            #expect(F.squash(detail) == expected)
        }
        #expect(content(at: F.date(6, 20), meetings: []).sections == [], "an empty store lists nothing")
    }

    @Test func locationsThatAreNotPlaces() throws {
        let hybrid = Meeting(id: "h", title: "Hybrid", start: F.date(6, 9), end: F.date(6, 10), location: "Sala Retiro; Microsoft Teams Meeting")
        let bareLink = Meeting(id: "l", title: "Link", start: F.date(6, 11), end: F.date(6, 12), location: "meet.google.com/abc-defg-hij")
        let dialIn = Meeting(id: "p", title: "Call", start: F.date(6, 13), end: F.date(6, 14), location: "Tel: +34 600 123 456")
        let rows = content(at: F.date(5, 21), meetings: [hybrid, bareLink, dialIn]).sections.first?.rows ?? []
        try #require(rows.count == 3, "expected 3 rows, got \(rows.map(\.id))")

        #expect(rows[0].detail == .location("Sala Retiro"))
        #expect(rows[0].action == .directions(LocationFormatter.directionsURL(to: "Sala Retiro")!))
        for row in rows.dropFirst() {
            #expect(row.detail == nil, "\(row.meeting.title)")
            #expect(row.action == nil, "\(row.meeting.title)")
        }

        guard case .next(let card) = content(at: F.date(6, 8), meetings: [hybrid, bareLink, dialIn]).hero else {
            Issue.record("expected next")
            return
        }
        #expect(card.location == "Sala Retiro")
    }

    @Test func heroUsesAlertableMeetingsOnly() {
        let result = content(at: F.date(6, 12, 28))
        guard case .next(let card) = result.hero else {
            Issue.record("expected next, got \(result.hero)")
            return
        }
        #expect(card.meeting.id == "lunch")
        let optedIn = content(at: F.date(6, 12, 28), alertable: F.week)
        guard case .startingSoon(let soon) = optedIn.hero else {
            Issue.record("expected startingSoon, got \(optedIn.hero)")
            return
        }
        #expect(soon.meeting.id == "ooo")
    }

    @Test func endedMeetingsAreLeftOut() {
        let result = content(at: F.date(6, 17, 30))
        let listed = result.sections.flatMap(ids)
        #expect(!listed.contains("plan"))
        #expect(!listed.contains("lunch"))
        #expect(!listed.contains("ooo"))
    }

    @Test func overlaps() {
        #expect(PanelPresenter.overlap(for: F.planning, in: F.week)?.id == "val")
        #expect(PanelPresenter.overlap(for: F.workshop, in: F.week) == nil, "only the later meeting is flagged")
        #expect(PanelPresenter.overlap(for: F.lunch, in: F.week) == nil, "out-of-office blocks never count")
        #expect(PanelPresenter.overlap(for: F.outOfOffice, in: F.week) == nil)

        let first = Meeting(id: "a", title: "Alpha", start: F.date(6, 9), end: F.date(6, 10))
        let second = Meeting(id: "b", title: "Bravo", start: F.date(6, 9), end: F.date(6, 9, 30))
        #expect(PanelPresenter.overlap(for: first, in: [first, second]) == nil)
        #expect(PanelPresenter.overlap(for: second, in: [first, second])?.id == "a")

        let shortEarlier = Meeting(id: "c", title: "Short", start: F.date(6, 8, 30), end: F.date(6, 9, 15))
        let longEarlier = Meeting(id: "d", title: "Long", start: F.date(6, 8), end: F.date(6, 12))
        let late = Meeting(id: "e", title: "Late", start: F.date(6, 9, 10), end: F.date(6, 9, 40))
        #expect(PanelPresenter.overlap(for: late, in: [shortEarlier, longEarlier, late])?.id == "d")

        let backToBack = Meeting(id: "f", title: "Next", start: F.date(6, 10), end: F.date(6, 11))
        #expect(PanelPresenter.overlap(for: backToBack, in: [first, backToBack]) == nil)
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

    // The Events choices reach the panel through the meetings it's given: excluded ones aren't listed,
    // and only Show and alert ones can take the card.
    @Test func theListAndTheCardFollowTheEventsChoices() {
        func panel(_ outOfOffice: EventVisibility, at now: Date) -> PanelContent {
            content(
                at: now,
                meetings: MeetingFilter.visible(F.week, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: outOfOffice),
                alertable: MeetingFilter.alertable(F.week, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: outOfOffice)
            )
        }
        let shown = panel(.listOnly, at: F.date(5, 21, 30)).sections.flatMap(ids)
        #expect(shown.contains(F.outOfOffice.id))
        #expect(panel(.showAndAlert, at: F.date(5, 21, 30)).sections.flatMap(ids) == shown)
        #expect(panel(.exclude, at: F.date(5, 21, 30)).sections.flatMap(ids) == shown.filter { $0 != F.outOfOffice.id })

        // 12:28 PM, two minutes before the out-of-office block: it takes the card only with Show and alert.
        #expect(panel(.listOnly, at: F.date(6, 12, 28)).hero.card?.meeting.id != F.outOfOffice.id)
        #expect(panel(.showAndAlert, at: F.date(6, 12, 28)).hero.card?.meeting.id == F.outOfOffice.id)
    }

    @Test func theStartingSoonCardFollowsTheMenuBarPillsWindow() {
        let usual = content(at: F.date(6, 12, 52))
        guard case .next = usual.hero else {
            Issue.record("expected next, got \(usual.hero)")
            return
        }
        let wider = content(at: F.date(6, 12, 52), startingSoonWindow: 10 * 60)
        guard case .startingSoon(let card) = wider.hero else {
            Issue.record("expected startingSoon, got \(wider.hero)")
            return
        }
        #expect(card.label == "Starts in 8 min")
    }

    // MARK: Today | 7 Days

    private func filteredTitles(_ state: PanelFilterState) -> [String] {
        state.sections.map { [$0.title, F.squash($0.subtitle)].compactMap { $0 }.joined(separator: " / ") }
    }

    @Test func todayListsTodayAndTheWeekAddsTheFollowingDays() {
        let result = content(at: F.date(6, 10, 45))
        let today = result.filtered(by: .today)
        #expect(today.isShown)
        #expect(today.isTodayAvailable)
        #expect(today.effective == .today)
        #expect(filteredTitles(today) == ["Today"])
        #expect(today.sections.flatMap(ids) == ["ooo", "lunch", "val", "plan"])

        let week = result.filtered(by: .week)
        #expect(week.effective == .week)
        #expect(week.sections == result.sections, "7 Days is the whole list")
        #expect(Array(week.sections.prefix(today.sections.count)) == today.sections,
                "switching keeps today's sections first; the week only adds day headings and the days after")
    }

    @Test func todayKeepsWhatIsOnNow() {
        let state = content(at: F.date(6, 15, 56)).filtered(by: .today)
        #expect(filteredTitles(state) == ["Now", "Today"])
        #expect(state.sections.flatMap(ids) == ["val", "plan"])
    }

    // Evening: the old app's Today showed an empty list here. Today is dimmed and the week shows.
    @Test func nothingLeftTodayDimsTodayAndShowsTheWeek() {
        let state = content(at: F.date(5, 21, 30)).filtered(by: .today)
        #expect(state.isShown)
        #expect(!state.isTodayAvailable)
        #expect(state.effective == .week)
        #expect(filteredTitles(state) == ["Tomorrow / \(us("EEEdMMM", 6))", "Wednesday / \(us("dMMM", 7))", "Thursday / \(us("dMMM", 8))"])
    }

    @Test func duringTheDaysLastMeetingTodayIsDimmed() {
        let result = content(at: F.date(6, 17, 30))
        guard case .now(let card) = result.hero else {
            Issue.record("expected now, got \(result.hero)")
            return
        }
        #expect(card.meeting.id == "val")
        let state = result.filtered(by: .today)
        #expect(!state.isTodayAvailable)
        #expect(state.effective == .week)
    }

    @Test func outOfOfficeRowsAloneDoNotMakeToday() {
        let away = Meeting(id: "away", title: "Out of office", start: F.date(6, 18), end: F.date(6, 23), isOutOfOffice: true)
        let state = content(at: F.date(6, 18, 30), meetings: [away, F.review]).filtered(by: .today)
        #expect(state.effective == .week, "a today made only of out-of-office rows would be an empty list in all but name")
        #expect(state.sections.flatMap(ids) == ["away", "rev"], "the week still lists the out-of-office block")
    }

    @Test func theSwitchHidesWhenNothingComesAfterToday() {
        let state = content(at: F.date(6, 10, 45), meetings: [F.lunch, F.workshop]).filtered(by: .week)
        #expect(!state.isShown)
        #expect(state.sections.flatMap(ids) == ["lunch", "val"])
        #expect(!content(at: F.date(6, 20), meetings: []).filtered(by: .today).isShown)
    }

    @Test func daySectionsAreLaterAndTodaysAreToday() {
        let result = content(at: F.date(6, 15, 56))
        #expect(result.sections.map(\.kind) == [.now, .today, .later, .later])
    }

    // The card picks like the menu bar: the accepted call at 4:00 PM, not the Maybe block running since 3:00,
    // which is listed under Now (not "Also now", since it isn't the card's).
    @Test func theCardPicksTheAcceptedMeetingOverAMaybeBlock() {
        var maybeWorkshop = F.workshop
        maybeWorkshop.myStatus = .tentative
        let result = content(at: F.date(6, 15, 13), meetings: [maybeWorkshop, F.planning])
        guard case .next(let card) = result.hero else {
            Issue.record("expected next, got \(result.hero)")
            return
        }
        #expect(card.meeting.id == "plan")
        #expect(result.sections.first?.title == "Now")
        #expect(result.sections.first.map(ids) == ["val"])

        let duringTheCall = content(at: F.date(6, 16, 20), meetings: [maybeWorkshop, F.planning])
        guard case .now(let nowCard) = duringTheCall.hero else {
            Issue.record("expected now, got \(duringTheCall.hero)")
            return
        }
        #expect(nowCard.meeting.id == "plan")
        #expect(duringTheCall.sections.first?.title == "Also now")
        #expect(duringTheCall.sections.first.map(ids) == ["val"])
    }

    // An accepted Workshop with a Maybe call inside it: the call still gets the starting-soon card (its alert
    // fires), but once it runs, the card goes back to the accepted Workshop.
    @Test func aMaybeCallInsideAnAcceptedMeetingGetsTheStartingSoonCardOnly() {
        var maybePlanning = F.planning
        maybePlanning.myStatus = .tentative
        let soon = content(at: F.date(6, 15, 56), meetings: [F.workshop, maybePlanning])
        guard case .startingSoon(let soonCard) = soon.hero else {
            Issue.record("expected startingSoon, got \(soon.hero)")
            return
        }
        #expect(soonCard.meeting.id == "plan")
        let running = content(at: F.date(6, 16, 20), meetings: [F.workshop, maybePlanning])
        guard case .now(let nowCard) = running.hero else {
            Issue.record("expected now, got \(running.hero)")
            return
        }
        #expect(nowCard.meeting.id == "val")
        #expect(running.sections.first.map(ids) == ["plan"], "the Maybe call is listed under Also now")
    }

    // Today: "Now", then "Upcoming events" with today's rows and no day heading. 7 Days: the same "Upcoming
    // events", with each day (Today, Tomorrow, Thursday) as a heading under it, as the user asked.
    @Test func upcomingEventsGroupsTheDaysUnderOneHeading() {
        let result = content(at: F.date(6, 15, 56))
        let today = result.filtered(by: .today)
        #expect(today.now?.title == "Now")
        #expect(today.now.map(ids) == ["val"])
        #expect(today.upcoming.flatMap(ids) == ["plan"])
        #expect(!today.showsDayHeadings)

        let week = result.filtered(by: .week)
        #expect(week.now.map(ids) == ["val"])
        #expect(week.upcoming.map(\.title) == ["Today", "Tomorrow", "Thursday"])
        #expect(week.showsDayHeadings)

        let onlyToday = content(at: F.date(6, 10, 45), meetings: [F.lunch, F.workshop]).filtered(by: .week)
        #expect(!onlyToday.showsDayHeadings, "nothing after today: a lone Today heading would say nothing")
        #expect(PanelFilterState.upcomingTitle == "Upcoming events")
    }

    // MARK: Dismissed events

    private func row(_ id: String, in content: PanelContent) -> PanelRow? {
        content.sections.lazy.flatMap(\.rows).first { $0.id == id }
    }

    // Later artboard, 10:45 AM: lunch is next. Dismissed, the card goes to the Workshop, and Today keeps lunch in
    // its place, marked, with its Directions button.
    @Test func aDismissedNextMeetingGivesTheCardToTheOneAfter() throws {
        let result = content(at: F.date(6, 10, 45), dismissed: [F.lunch.id])
        guard case .next(let card) = result.hero else {
            Issue.record("expected next, got \(result.hero)")
            return
        }
        #expect(card.meeting.id == "val")
        #expect(card.label == "Next · in 4 h 15 min")
        #expect(result.sections.first.map(ids) == ["ooo", "lunch", "val", "plan"])

        let lunch = try #require(row("lunch", in: result), "expected lunch's row")
        #expect(lunch.dismissal == .dismissed(asksScope: false))
        #expect(lunch.detail == .dismissed("Dismissed"), "in place of its location")
        #expect(lunch.action == .directions(LocationFormatter.directionsURL(to: F.lunch.location!)!), "joining is still allowed")
        #expect(!lunch.isMuted, "muted is for out-of-office blocks")
    }

    // Busy artboard, 3:56 PM: Planning is starting soon. Dismissed, the Workshop in progress takes the card.
    @Test func aDismissedStartingSoonMeetingGivesTheCardToTheOneInProgress() {
        let result = content(at: F.date(6, 15, 56), dismissed: [F.planning.id])
        guard case .now(let card) = result.hero else {
            Issue.record("expected now, got \(result.hero)")
            return
        }
        #expect(card.meeting.id == "val")
        #expect(card.label == "Now · 3 h 34 min left")
        #expect(titles(result) == ["Today", "Tomorrow / \(us("EEEdMMM", 7))", "Thursday / \(us("dMMM", 8))"])
        #expect(result.sections.first.map(ids) == ["plan"], "yet to start, it stays under Today")
        #expect(row("plan", in: result)?.detail == .dismissed("Dismissed"), "no overlap warning on a dismissed row")
        #expect(row("plan", in: result)?.action == .join(F.meet))
    }

    // Meeting artboard, 4:20 PM, in two meetings: the dismissed one is listed under Also now with its time left.
    @Test func aDismissedMeetingInProgressIsListedUnderAlsoNow() {
        let undismissed = content(at: F.date(6, 16, 20))
        guard case .progress(_, let left)? = row("val", in: undismissed)?.detail else {
            Issue.record("expected the Workshop's progress")
            return
        }
        #expect(left == "3 h 10 min left")

        let result = content(at: F.date(6, 16, 20), dismissed: [F.workshop.id])
        guard case .now(let card) = result.hero else {
            Issue.record("expected now, got \(result.hero)")
            return
        }
        #expect(card.meeting.id == "plan")
        #expect(result.sections.first?.title == "Also now")
        #expect(result.sections.first.map(ids) == ["val"])
        let workshop = row("val", in: result)
        #expect(workshop?.dismissal == .dismissed(asksScope: false))
        #expect(workshop?.detail == .dismissed("Dismissed · \(left)"), "the time left as the progress line words it, without the bar")
        #expect(workshop?.action == .join(F.meet))

        // The card's own meeting dismissed: the other one in progress takes the card, and Also now lists the dismissed one.
        let other = content(at: F.date(6, 16, 20), dismissed: [F.planning.id])
        guard case .now(let otherCard) = other.hero else {
            Issue.record("expected now, got \(other.hero)")
            return
        }
        #expect(otherCard.meeting.id == "val")
        #expect(otherCard.label == "Now · 3 h 10 min left")
        #expect(other.sections.first?.title == "Also now")
        #expect(other.sections.first.map(ids) == ["plan"])
        #expect(row("plan", in: other)?.detail == .dismissed("Dismissed · 40 min left"))
    }

    // 1:30 PM, at lunch: dismissed, the card shows the Workshop coming up, so lunch is listed under Now.
    @Test func aDismissedMeetingInProgressIsListedUnderNowWhenTheCardIsNotNow() {
        let result = content(at: F.date(6, 13, 30), dismissed: [F.lunch.id])
        guard case .next(let card) = result.hero else {
            Issue.record("expected next, got \(result.hero)")
            return
        }
        #expect(card.meeting.id == "val")
        #expect(card.label == "Next · in 1 h 30 min")
        #expect(result.sections.first?.title == "Now")
        #expect(result.sections.first.map(ids) == ["ooo", "lunch"])
        #expect(row("lunch", in: result)?.detail == .dismissed("Dismissed · 30 min left"))
        #expect(row("ooo", in: result)?.dismissal == nil)
    }

    @Test func nextUpSkipsDismissedMeetings() {
        func detail(_ dismissed: Set<String>) -> String? {
            guard case .nothingToday(let detail) = content(at: F.date(5, 21, 30), dismissed: dismissed).hero else { return nil }
            return F.squash(detail)
        }
        #expect(detail([]) == "Next up tomorrow at 1:00 PM, in 15 h 30 min")
        #expect(detail([F.lunch.id]) == "Next up tomorrow at 3:00 PM, in 17 h 30 min")
        #expect(detail([F.lunch.id, F.workshop.id, F.planning.id]) == "Next up Wednesday at 9:10 AM")
        #expect(detail(Set(F.alertable.map(\.id))) == "Nothing in the next 7 days")
        #expect(content(at: F.date(5, 21, 30), dismissed: Set(F.alertable.map(\.id))).sections.flatMap(ids)
                == content(at: F.date(5, 21, 30)).sections.flatMap(ids), "everything dismissed is still listed")
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
                dismissed: MeetingFilter.dismissedIDs(all, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice, dismissed: stored),
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
        let planningDismissed = content(at: F.date(5, 21, 30), dismissed: [F.planning.id])
        #expect(row("plan", in: planningDismissed)?.detail == .dismissed("Dismissed"))
        #expect(row("val", in: planningDismissed)?.detail == nil)

        // 3:56 PM: Planning's card warns about the Workshop until the Workshop is dismissed.
        let soon = content(at: F.date(6, 15, 56), dismissed: [F.workshop.id])
        guard case .startingSoon(let card) = soon.hero else {
            Issue.record("expected startingSoon, got \(soon.hero)")
            return
        }
        #expect(card.meeting.id == "plan")
        #expect(card.overlap == nil)
        #expect(soon.sections.first?.title == "Now")
        #expect(soon.sections.first.map(ids) == ["val"])
        #expect(row("val", in: soon)?.detail == .dismissed("Dismissed · 3 h 34 min left"))

        // Of two meetings running when a third starts, a dismissed one is skipped and the other one named.
        let shortEarlier = Meeting(id: "c", title: "Short", start: F.date(6, 8, 30), end: F.date(6, 9, 15))
        let longEarlier = Meeting(id: "d", title: "Long", start: F.date(6, 8), end: F.date(6, 12))
        let late = Meeting(id: "e", title: "Late", start: F.date(6, 9, 10), end: F.date(6, 9, 40))
        let meetings = [shortEarlier, longEarlier, late]
        #expect(row("e", in: content(at: F.date(6, 7), meetings: meetings))?.detail == .overlap("Overlaps Long"))
        #expect(row("e", in: content(at: F.date(6, 7), meetings: meetings, dismissed: ["d"]))?.detail == .overlap("Overlaps Short"))
        guard case .next(let lateCard) = content(at: F.date(6, 9), meetings: [longEarlier, late], dismissed: ["d"]).hero else {
            Issue.record("expected the late meeting's card")
            return
        }
        #expect(lateCard.overlap == nil, "the card's line ignores the dismissed meeting too")
    }

    // 2:40 PM: the Workshop and Planning are all that's left today. Both dismissed, they're still on, so Today stays
    // available and lists them, while the card has nothing left today.
    @Test func todayStaysAvailableWithOnlyDismissedMeetingsLeft() {
        let result = content(at: F.date(6, 14, 40), dismissed: [F.workshop.id, F.planning.id])
        guard case .nothingToday(let detail) = result.hero else {
            Issue.record("expected nothingToday, got \(result.hero)")
            return
        }
        #expect(F.squash(detail) == "Next up tomorrow at 9:10 AM, in 18 h 30 min")
        let today = result.filtered(by: .today)
        #expect(today.isTodayAvailable)
        #expect(today.effective == .today)
        #expect(filteredTitles(today) == ["Today"])
        #expect(today.sections.flatMap(ids) == ["val", "plan"])

        // 5:30 PM, the day's last meeting dismissed: it's under Now, and Today isn't dimmed (compare
        // duringTheDaysLastMeetingTodayIsDimmed).
        let evening = content(at: F.date(6, 17, 30), dismissed: [F.workshop.id])
        guard case .nothingToday = evening.hero else {
            Issue.record("expected nothingToday, got \(evening.hero)")
            return
        }
        let state = evening.filtered(by: .today)
        #expect(state.isTodayAvailable)
        #expect(filteredTitles(state) == ["Now"])
        #expect(row("val", in: evening)?.detail == .dismissed("Dismissed · 2 h left"))
    }

    // MARK: Repeating events

    /// The planning call as a repeating event: Tuesday's (the artboards' "plan"), Wednesday's and Thursday's,
    /// all at 4:00 PM, one series.
    private func planning(_ day: Int) -> Meeting {
        Meeting(id: day == 6 ? "plan" : "plan\(day)", title: F.planning.title, start: F.date(day, 16), end: F.date(day, 17),
                joinURL: F.meet, seriesID: "planning")
    }

    private var weekWithSeries: [Meeting] {
        F.week.map { $0.id == "plan" ? planning(6) : $0 } + [planning(7), planning(8)]
    }

    /// The panel for `stored` dismissals, through the same filters as the store.
    private func content(at now: Date, stored: DismissedEvents) -> PanelContent {
        let meetings = weekWithSeries
        return content(
            at: now,
            meetings: meetings,
            alertable: MeetingFilter.alertable(meetings, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .listOnly, dismissed: stored),
            dismissed: MeetingFilter.dismissedIDs(meetings, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .listOnly, dismissed: stored),
            dismissedBySeries: MeetingFilter.dismissedBySeriesIDs(
                meetings, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .listOnly, dismissed: stored)
        )
    }

    // Whether a row's button asks This Event or All Future Events: Dismiss on any repeating event; Restore only on
    // an occurrence dismissed with its series. One dismissed on its own restores at once (the user's ask), even
    // though it repeats; a one-off never asks.
    @Test func whichButtonsAskThisEventOrAllFutureEvents() {
        let none = content(at: F.date(6, 15, 56), stored: DismissedEvents())
        #expect(dismissals(none) == [
            "val": .dismissable(asksScope: false), "plan": .dismissable(asksScope: true), "rev": .dismissable(asksScope: false),
            "one": .dismissable(asksScope: false), "plan7": .dismissable(asksScope: true), "road": .dismissable(asksScope: false),
            "plan8": .dismissable(asksScope: true), "thu": .dismissable(asksScope: false),
        ], "Dismiss asks on the planning calls only")
        // The card's Dismiss, which has no row, asks by the same rule.
        #expect(PanelRow.Dismissal.dismissable(for: planning(6)) == .dismissable(asksScope: true))
        #expect(PanelRow.Dismissal.dismissable(for: F.workshop) == .dismissable(asksScope: false))

        let one = content(at: F.date(6, 15, 56), stored: DismissedEvents().dismissing(planning(7)))
        #expect(row("plan7", in: one)?.dismissal == .dismissed(asksScope: false), "dismissed on its own: Restore acts at once")
        #expect(row("plan8", in: one)?.dismissal == .dismissable(asksScope: true), "Thursday's Dismiss still asks")

        let rule = content(at: F.date(6, 15, 56), stored: DismissedEvents().dismissing(planning(7), scope: .allFutureEvents))
        #expect(row("plan7", in: rule)?.dismissal == .dismissed(asksScope: true), "dismissed with its series: Restore asks")
        #expect(row("plan8", in: rule)?.dismissal == .dismissed(asksScope: true))

        // Restored on its own inside the rule, Wednesday's is a plain repeating row again, whose Dismiss asks;
        // dismissed again with This Event, the rule covers it once more, so its Restore asks.
        let excepted = DismissedEvents().dismissing(planning(7), scope: .allFutureEvents).restoring(planning(7))
        #expect(row("plan7", in: content(at: F.date(6, 15, 56), stored: excepted))?.dismissal == .dismissable(asksScope: true))
        #expect(row("plan7", in: content(at: F.date(6, 15, 56), stored: excepted.dismissing(planning(7))))?.dismissal
                == .dismissed(asksScope: true))
    }

    private func dismissals(_ content: PanelContent) -> [String: PanelRow.Dismissal?] {
        Dictionary(uniqueKeysWithValues: content.sections.flatMap(\.rows).map { ($0.id, $0.dismissal) })
    }

    // Busy artboard, 3:56 PM, Planning starting soon. All Future Events: the Workshop in progress takes the card,
    // and Wednesday's and Thursday's planning calls are listed as dismissed too, so Wednesday's no longer
    // clashes with the roadmap review.
    @Test func allFutureEventsOfASeriesAreListedAsDismissed() {
        let undismissed = content(at: F.date(6, 15, 56), stored: DismissedEvents())
        guard case .startingSoon(let soon) = undismissed.hero else {
            Issue.record("expected startingSoon, got \(undismissed.hero)")
            return
        }
        #expect(soon.meeting.id == "plan")
        #expect(row("road", in: undismissed)?.detail == .overlap("Overlaps Ana/Luis: Product Planning"))

        let result = content(at: F.date(6, 15, 56), stored: DismissedEvents().dismissing(planning(6), scope: .allFutureEvents))
        guard case .now(let card) = result.hero else {
            Issue.record("expected now, got \(result.hero)")
            return
        }
        #expect(card.meeting.id == "val")
        #expect(dismissals(result) == [
            "plan": .dismissed(asksScope: true), "rev": .dismissable(asksScope: false), "one": .dismissable(asksScope: false),
            "plan7": .dismissed(asksScope: true), "road": .dismissable(asksScope: false), "plan8": .dismissed(asksScope: true),
            "thu": .dismissable(asksScope: false),
        ], "the Workshop has the card, so it isn't listed")
        #expect(row("plan7", in: result)?.detail == .dismissed("Dismissed"))
        #expect(row("road", in: result)?.detail == nil, "a dismissed occurrence clashes with nothing")

        // This Event: Tuesday's only.
        let one = content(at: F.date(6, 15, 56), stored: DismissedEvents().dismissing(planning(6)))
        guard case .now(let oneCard) = one.hero else {
            Issue.record("expected now, got \(one.hero)")
            return
        }
        #expect(oneCard.meeting.id == "val")
        #expect(row("plan", in: one)?.dismissal == .dismissed(asksScope: false))
        #expect(row("plan7", in: one)?.dismissal == .dismissable(asksScope: true))
        #expect(row("plan8", in: one)?.dismissal == .dismissable(asksScope: true))
        #expect(row("road", in: one)?.detail == .overlap("Overlaps Ana/Luis: Product Planning"))
    }

    // Wednesday 3:58 PM: Wednesday's planning call and the roadmap review both start at 4:00. With the series
    // dismissed from Tuesday on, the review takes the starting-soon card, with no overlap to warn about.
    @Test func theCardSkipsADismissedSeriesOccurrence() {
        let undismissed = content(at: F.date(7, 15, 58), stored: DismissedEvents())
        guard case .startingSoon(let first) = undismissed.hero else {
            Issue.record("expected startingSoon, got \(undismissed.hero)")
            return
        }
        #expect(first.meeting.id == "plan7")

        let result = content(at: F.date(7, 15, 58), stored: DismissedEvents().dismissing(planning(6), scope: .allFutureEvents))
        guard case .startingSoon(let card) = result.hero else {
            Issue.record("expected startingSoon, got \(result.hero)")
            return
        }
        #expect(card.meeting.id == "road")
        #expect(card.overlap == nil)
        #expect(row("plan7", in: result)?.dismissal == .dismissed(asksScope: true))
    }

    // Restore This Event on Wednesday's: that one comes back and the rest of the series stays dismissed. Restore
    // All Future Events on Wednesday's: Wednesday's and Thursday's come back, while Tuesday's, earlier and still
    // listed, stays dismissed.
    @Test func restoringPartOfADismissedSeries() {
        let rule = DismissedEvents().dismissing(planning(6), scope: .allFutureEvents)

        let thisEvent = content(at: F.date(6, 15, 56), stored: rule.restoring(planning(7)))
        #expect(row("plan", in: thisEvent)?.dismissal == .dismissed(asksScope: true))
        #expect(row("plan7", in: thisEvent)?.dismissal == .dismissable(asksScope: true))
        #expect(row("plan8", in: thisEvent)?.dismissal == .dismissed(asksScope: true))
        #expect(row("road", in: thisEvent)?.detail == .overlap("Overlaps Ana/Luis: Product Planning"))

        let future = content(at: F.date(6, 15, 56), stored: rule.restoring(planning(7), scope: .allFutureEvents))
        guard case .now(let card) = future.hero else {
            Issue.record("expected now, got \(future.hero)")
            return
        }
        #expect(card.meeting.id == "val", "Tuesday's is still dismissed")
        #expect(row("plan", in: future)?.dismissal == .dismissed(asksScope: true))
        #expect(row("plan7", in: future)?.dismissal == .dismissable(asksScope: true))
        #expect(row("plan8", in: future)?.dismissal == .dismissable(asksScope: true))

        let all = content(at: F.date(6, 15, 56), stored: rule.restoring(planning(6), scope: .allFutureEvents))
        #expect(all == content(at: F.date(6, 15, 56), stored: DismissedEvents()))
    }

    @Test func dismissCopy() {
        #expect(DismissCopy.dismissTitle == "Dismiss")
        #expect(DismissCopy.restoreTitle == "Restore")
        #expect(DismissCopy.dismissedTitle == "Dismissed")
        #expect(DismissCopy.dismissedDetail(left: nil) == "Dismissed")
        #expect(DismissCopy.dismissedDetail(left: "34 min left") == "Dismissed · 34 min left")
        #expect(DismissCopy.dismissAccessibilityLabel(for: F.workshop, asksScope: false) == "Dismiss Workshop")
        #expect(DismissCopy.restoreAccessibilityLabel(for: F.workshop, asksScope: false) == "Restore Workshop")
        #expect(DismissCopy.rowDismissHelp
                == "Dismiss: no full-screen alert, and it leaves the menu bar and the top card. It stays in this list until it ends.")
        #expect(DismissCopy.cardDismissHelp
                == "Dismiss: no full-screen alert, and it leaves the menu bar and this card. It stays in the list until it ends.")
        #expect(DismissCopy.restoreHelp == "Restore: its full-screen alert and the menu bar come back.")
        for help in [DismissCopy.rowDismissHelp, DismissCopy.cardDismissHelp, DismissCopy.restoreHelp] {
            #expect(!(help.contains("Don’t") || help.contains("Don't")), "\(help)")
        }
        #expect(DismissCopy.rowDismissHelp(asksScope: false) == DismissCopy.rowDismissHelp)
        #expect(DismissCopy.cardDismissHelp(asksScope: false) == DismissCopy.cardDismissHelp)
        #expect(DismissCopy.restoreHelp(asksScope: false) == DismissCopy.restoreHelp)
    }

    // A repeating event's buttons open a menu worded like macOS Calendar's question; its labels and help tags say so.
    @Test func dismissCopyForARepeatingEvent() {
        let repeating = planning(6)
        #expect(DismissScope.allCases == [.thisEvent, .allFutureEvents], "the menus' order")
        #expect(DismissCopy.dismissChoice(.thisEvent) == "Dismiss This Event")
        #expect(DismissCopy.dismissChoice(.allFutureEvents) == "Dismiss All Future Events")
        #expect(DismissCopy.restoreChoice(.thisEvent) == "Restore This Event")
        #expect(DismissCopy.restoreChoice(.allFutureEvents) == "Restore All Future Events")
        #expect(DismissCopy.dismissAccessibilityLabel(for: repeating, asksScope: true) == "Dismiss Ana/Luis: Product Planning, opens a menu")
        #expect(DismissCopy.restoreAccessibilityLabel(for: repeating, asksScope: true) == "Restore Ana/Luis: Product Planning, opens a menu")
        #expect(DismissCopy.restoreAccessibilityLabel(for: repeating, asksScope: false) == "Restore Ana/Luis: Product Planning",
                "dismissed on its own, Restore acts at once")
        #expect(DismissCopy.rowDismissHelp(asksScope: true)
                == "Dismiss: no full-screen alert, and it leaves the menu bar and the top card. It stays in this list until it ends. It repeats: the menu offers this event or all future events.")
        #expect(DismissCopy.cardDismissHelp(asksScope: true)
                == "Dismiss: no full-screen alert, and it leaves the menu bar and this card. It stays in the list until it ends. It repeats: the menu offers this event or all future events.")
        #expect(DismissCopy.restoreHelp(asksScope: true)
                == "Restore: its full-screen alert and the menu bar come back. It repeats: the menu offers this event or all future events.")
    }
}
