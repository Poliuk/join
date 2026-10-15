import XCTest
@testable import JoinCore

final class PanelPresenterTests: XCTestCase {
    typealias F = MenuBarFixtures

    /// `alertable` defaults to the meetings that aren't out-of-office blocks or `dismissed`, as the store passes them.
    private func content(at now: Date, meetings: [Meeting] = F.week, alertable: [Meeting]? = nil, dismissed: Set<String> = [],
                         startingSoonWindow: TimeInterval = MenuBarPresenter.startingSoonWindow,
                         locale: Locale = F.us) -> PanelContent {
        PanelPresenter.content(meetings: meetings, alertable: alertable ?? meetings.filter { !$0.isOutOfOffice && !dismissed.contains($0.id) },
                               dismissed: dismissed, now: now,
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
    func testNothingLeftToday() {
        let result = content(at: F.date(5, 21, 30))
        guard case .nothingToday(let detail) = result.hero else { return XCTFail("expected nothingToday, got \(result.hero)") }
        XCTAssertEqual(F.squash(detail), "Next up tomorrow at 1:00 PM, in 15 h 30 min")
        XCTAssertEqual(titles(result), ["Tomorrow / \(us("EEEdMMM", 6))", "Wednesday / \(us("dMMM", 7))", "Thursday / \(us("dMMM", 8))"])
        XCTAssertEqual(result.sections.map(ids), [["ooo", "lunch", "val", "plan"], ["rev", "one", "road"], ["thu"]])
    }

    // en_GB: day before month and a 24-hour clock, e.g. "Tomorrow / Tue 6 Oct" and "Next up Mon 12 Oct at 09:00".
    // ICU's punctuation (a comma after the weekday on macOS 14) comes from Foundation rather than being pinned.
    func testDatesAndTimesFollowTheLocale() {
        func gb(_ template: String, _ day: Int) -> String { F.formatted(template, day: day, locale: F.gb) }
        XCTAssertEqual(titles(content(at: F.date(5, 21, 30), locale: F.gb)),
                       ["Tomorrow / \(gb("EEEdMMM", 6))", "Wednesday / \(gb("dMMM", 7))", "Thursday / \(gb("dMMM", 8))"])
        let nextWeek = content(at: F.date(5, 10), meetings: [F.nextMonday], locale: F.gb)
        guard case .nothingToday(let detail) = nextWeek.hero else { return XCTFail("expected nothingToday, got \(nextWeek.hero)") }
        XCTAssertEqual(F.squash(detail), "Next up \(gb("EEEdMMM", 12)) at 09:00", "a week ahead: the date, and a 24-hour time")
    }

    func testRowsFromTheDesign() {
        let tuesday = content(at: F.date(5, 21, 30)).sections.first?.rows ?? []
        guard tuesday.count == 4 else { return XCTFail("expected Tuesday's 4 rows, got \(tuesday.map(\.id))") }

        let outOfOffice = tuesday[0]
        XCTAssertTrue(outOfOffice.isMuted)
        XCTAssertNil(outOfOffice.action)
        XCTAssertNil(outOfOffice.detail)
        XCTAssertEqual(F.squash(outOfOffice.startTime), "12:30 PM")
        XCTAssertEqual(F.squash(outOfOffice.endTime), "2:30 PM")

        let lunch = tuesday[1]
        XCTAssertFalse(lunch.isMuted)
        XCTAssertEqual(lunch.detail, .location("C. de Ruiz de Alarcón, 23 · Retiro"))
        XCTAssertEqual(lunch.action, .directions(LocationFormatter.directionsURL(to: F.lunch.location!)!))

        let workshop = tuesday[2]
        XCTAssertNil(workshop.detail)
        XCTAssertEqual(workshop.action, .join(F.meet))

        let planning = tuesday[3]
        XCTAssertEqual(planning.detail, .overlap("Overlaps Workshop"))
        XCTAssertEqual(planning.action, .join(F.meet))
    }

    // Later artboard: Tuesday 10:45 AM, the next meeting is later today.
    func testNextMeetingLaterToday() {
        let result = content(at: F.date(6, 10, 45))
        guard case .next(let card) = result.hero else { return XCTFail("expected next, got \(result.hero)") }
        XCTAssertEqual(card.meeting.id, "lunch")
        XCTAssertEqual(card.label, "Next · in 2 h 15 min")
        XCTAssertEqual(F.squash(card.timeRange), "1:00 – 2:00 PM")
        XCTAssertEqual(card.location, "C. de Ruiz de Alarcón, 23 · Retiro")
        XCTAssertNil(card.overlap, "out-of-office blocks never count as overlaps")
        XCTAssertNil(card.progress)
        XCTAssertEqual(card.action, .directions(LocationFormatter.directionsURL(to: F.lunch.location!)!))

        XCTAssertEqual(titles(result), ["Today", "Tomorrow / \(us("EEEdMMM", 7))", "Thursday / \(us("dMMM", 8))"])
        XCTAssertEqual(result.sections.first.map(ids), ["ooo", "lunch", "val", "plan"], "Today lists the hero's meeting too")
    }

    // Busy artboard: Tuesday 3:56 PM, a meeting starts in 4 minutes while another one runs.
    func testStartingSoonWinsOverAMeetingInProgress() {
        let result = content(at: F.date(6, 15, 56))
        guard case .startingSoon(let card) = result.hero else { return XCTFail("expected startingSoon, got \(result.hero)") }
        XCTAssertEqual(card.meeting.id, "plan")
        XCTAssertEqual(card.label, "Starts in 4 min")
        XCTAssertEqual(F.squash(card.overlap), "Overlaps Workshop, which runs until 7:30 PM")
        XCTAssertEqual(card.action, .join(F.meet))

        XCTAssertEqual(titles(result), ["Now", "Today", "Tomorrow / \(us("EEEdMMM", 7))", "Thursday / \(us("dMMM", 8))"])
        XCTAssertEqual(result.sections.prefix(2).map(ids), [["val"], ["plan"]], "the starting-soon meeting is also listed under Today")
        let nowRow = result.sections.first?.rows.first
        guard case .progress(let elapsed, let left) = nowRow?.detail else {
            return XCTFail("expected progress, got \(String(describing: nowRow?.detail))")
        }
        XCTAssertEqual(elapsed, 56.0 / 270.0, accuracy: 0.0001)
        XCTAssertEqual(left, "3 h 34 min left")
    }

    // Meeting artboard: Tuesday 4:20 PM, in two meetings at once.
    func testInAMeeting() {
        let result = content(at: F.date(6, 16, 20))
        guard case .now(let card) = result.hero else { return XCTFail("expected now, got \(result.hero)") }
        XCTAssertEqual(card.meeting.id, "plan", "the most recently started meeting gets the card")
        XCTAssertEqual(card.label, "Now · 40 min left")
        XCTAssertEqual(F.squash(card.timeRange), "4:00 – 5:00 PM")
        XCTAssertEqual(card.progress ?? -1, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertNil(card.overlap)
        XCTAssertEqual(card.action, .join(F.meet))

        XCTAssertEqual(titles(result), ["Also now", "Tomorrow / \(us("EEEdMMM", 7))", "Thursday / \(us("dMMM", 8))"])
        XCTAssertEqual(result.sections.first.map(ids), ["val"], "the meeting on the Now card isn't repeated")
        let alsoNow = result.sections.first?.rows.first
        guard case .progress(let elapsed, let left) = alsoNow?.detail else {
            return XCTFail("expected progress, got \(String(describing: alsoNow?.detail))")
        }
        XCTAssertEqual(elapsed, 80.0 / 270.0, accuracy: 0.0001)
        XCTAssertEqual(left, "3 h 10 min left")
    }

    func testNowSectionHoldsAnOngoingOutOfOfficeBlock() {
        let result = content(at: F.date(6, 13, 30))
        guard case .now(let card) = result.hero else { return XCTFail("expected now, got \(result.hero)") }
        XCTAssertEqual(card.meeting.id, "lunch")
        XCTAssertEqual(card.action, .directions(LocationFormatter.directionsURL(to: F.lunch.location!)!))
        XCTAssertEqual(titles(result).first, "Also now")
        XCTAssertEqual(result.sections.first.map(ids), ["ooo"])
        guard let row = result.sections.first?.rows.first else { return XCTFail("expected an Also now row") }
        XCTAssertTrue(row.isMuted)
        XCTAssertNil(row.detail)

        let afterLunch = content(at: F.date(6, 14, 10))
        guard case .next = afterLunch.hero else { return XCTFail("expected next, got \(afterLunch.hero)") }
        XCTAssertEqual(titles(afterLunch).prefix(2), ["Now", "Today"])
    }

    // "No more meetings today": a countdown only within 24 h (see testNothingLeftToday), the weekday within
    // the coming week, the date a week or more ahead.
    func testNextUpDetail() {
        let cases: [(now: Date, meetings: [Meeting], expected: String)] = [
            (F.date(6, 20), [F.thursday], "Next up Thursday at 10:00 AM"),
            (F.date(5, 10), [F.sunday], "Next up Sunday at 9:00 AM"),
            (F.date(5, 10), [F.nextMonday], "Next up \(us("EEEdMMM", 12)) at 9:00 AM"),
            (F.date(6, 20), [], "Nothing in the next 7 days"),
        ]
        for (now, meetings, expected) in cases {
            let result = content(at: now, meetings: meetings)
            guard case .nothingToday(let detail) = result.hero else {
                XCTFail("expected nothingToday for \(expected), got \(result.hero)"); continue
            }
            XCTAssertEqual(F.squash(detail), expected)
        }
        XCTAssertEqual(content(at: F.date(6, 20), meetings: []).sections, [], "an empty store lists nothing")
    }

    func testLocationsThatAreNotPlaces() {
        let hybrid = Meeting(id: "h", title: "Hybrid", start: F.date(6, 9), end: F.date(6, 10), location: "Sala Retiro; Microsoft Teams Meeting")
        let bareLink = Meeting(id: "l", title: "Link", start: F.date(6, 11), end: F.date(6, 12), location: "meet.google.com/abc-defg-hij")
        let dialIn = Meeting(id: "p", title: "Call", start: F.date(6, 13), end: F.date(6, 14), location: "Tel: +34 600 123 456")
        let rows = content(at: F.date(5, 21), meetings: [hybrid, bareLink, dialIn]).sections.first?.rows ?? []
        guard rows.count == 3 else { return XCTFail("expected 3 rows, got \(rows.map(\.id))") }

        XCTAssertEqual(rows[0].detail, .location("Sala Retiro"))
        XCTAssertEqual(rows[0].action, .directions(LocationFormatter.directionsURL(to: "Sala Retiro")!))
        for row in rows.dropFirst() {
            XCTAssertNil(row.detail, row.meeting.title)
            XCTAssertNil(row.action, row.meeting.title)
        }

        guard case .next(let card) = content(at: F.date(6, 8), meetings: [hybrid, bareLink, dialIn]).hero else { return XCTFail("expected next") }
        XCTAssertEqual(card.location, "Sala Retiro")
    }

    func testHeroUsesAlertableMeetingsOnly() {
        let result = content(at: F.date(6, 12, 28))
        guard case .next(let card) = result.hero else { return XCTFail("expected next, got \(result.hero)") }
        XCTAssertEqual(card.meeting.id, "lunch")
        let optedIn = content(at: F.date(6, 12, 28), alertable: F.week)
        guard case .startingSoon(let soon) = optedIn.hero else { return XCTFail("expected startingSoon, got \(optedIn.hero)") }
        XCTAssertEqual(soon.meeting.id, "ooo")
    }

    func testEndedMeetingsAreLeftOut() {
        let result = content(at: F.date(6, 17, 30))
        let listed = result.sections.flatMap(ids)
        XCTAssertFalse(listed.contains("plan"))
        XCTAssertFalse(listed.contains("lunch"))
        XCTAssertFalse(listed.contains("ooo"))
    }

    func testOverlaps() {
        XCTAssertEqual(PanelPresenter.overlap(for: F.planning, in: F.week)?.id, "val")
        XCTAssertNil(PanelPresenter.overlap(for: F.workshop, in: F.week), "only the later meeting is flagged")
        XCTAssertNil(PanelPresenter.overlap(for: F.lunch, in: F.week), "out-of-office blocks never count")
        XCTAssertNil(PanelPresenter.overlap(for: F.outOfOffice, in: F.week))

        let first = Meeting(id: "a", title: "Alpha", start: F.date(6, 9), end: F.date(6, 10))
        let second = Meeting(id: "b", title: "Bravo", start: F.date(6, 9), end: F.date(6, 9, 30))
        XCTAssertNil(PanelPresenter.overlap(for: first, in: [first, second]))
        XCTAssertEqual(PanelPresenter.overlap(for: second, in: [first, second])?.id, "a")

        let shortEarlier = Meeting(id: "c", title: "Short", start: F.date(6, 8, 30), end: F.date(6, 9, 15))
        let longEarlier = Meeting(id: "d", title: "Long", start: F.date(6, 8), end: F.date(6, 12))
        let late = Meeting(id: "e", title: "Late", start: F.date(6, 9, 10), end: F.date(6, 9, 40))
        XCTAssertEqual(PanelPresenter.overlap(for: late, in: [shortEarlier, longEarlier, late])?.id, "d")

        let backToBack = Meeting(id: "f", title: "Next", start: F.date(6, 10), end: F.date(6, 11))
        XCTAssertNil(PanelPresenter.overlap(for: backToBack, in: [first, backToBack]))
    }

    // Just before midnight a meeting at 12:03 AM is starting soon; its day's section lists it too.
    func testStartingSoonAfterMidnightIsListedUnderItsDay() {
        let early = Meeting(id: "early", title: "Early", start: F.date(7, 0, 3), end: F.date(7, 0, 30), joinURL: F.meet)
        let result = content(at: F.date(6, 23, 59), meetings: [early, F.review])
        guard case .startingSoon(let card) = result.hero else { return XCTFail("expected startingSoon, got \(result.hero)") }
        XCTAssertEqual(card.meeting.id, "early")
        XCTAssertEqual(titles(result), ["Tomorrow / \(us("EEEdMMM", 7))"])
        XCTAssertEqual(result.sections.map(ids), [["early", "rev"]])
    }

    // The Events choices reach the panel through the meetings it's given: excluded ones aren't listed,
    // and only Show and alert ones can take the card.
    func testTheListAndTheCardFollowTheEventsChoices() {
        func panel(_ outOfOffice: EventVisibility, at now: Date) -> PanelContent {
            content(
                at: now,
                meetings: MeetingFilter.visible(F.week, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: outOfOffice),
                alertable: MeetingFilter.alertable(F.week, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: outOfOffice)
            )
        }
        let shown = panel(.listOnly, at: F.date(5, 21, 30)).sections.flatMap(ids)
        XCTAssertTrue(shown.contains(F.outOfOffice.id))
        XCTAssertEqual(panel(.showAndAlert, at: F.date(5, 21, 30)).sections.flatMap(ids), shown)
        XCTAssertEqual(panel(.exclude, at: F.date(5, 21, 30)).sections.flatMap(ids), shown.filter { $0 != F.outOfOffice.id })

        // 12:28 PM, two minutes before the out-of-office block: it takes the card only with Show and alert.
        XCTAssertNotEqual(panel(.listOnly, at: F.date(6, 12, 28)).hero.card?.meeting.id, F.outOfOffice.id)
        XCTAssertEqual(panel(.showAndAlert, at: F.date(6, 12, 28)).hero.card?.meeting.id, F.outOfOffice.id)
    }

    func testTheStartingSoonCardFollowsTheMenuBarPillsWindow() {
        let usual = content(at: F.date(6, 12, 52))
        guard case .next = usual.hero else { return XCTFail("expected next, got \(usual.hero)") }
        let wider = content(at: F.date(6, 12, 52), startingSoonWindow: 10 * 60)
        guard case .startingSoon(let card) = wider.hero else { return XCTFail("expected startingSoon, got \(wider.hero)") }
        XCTAssertEqual(card.label, "Starts in 8 min")
    }

    // MARK: Today | 7 Days

    private func filteredTitles(_ state: PanelFilterState) -> [String] {
        state.sections.map { [$0.title, F.squash($0.subtitle)].compactMap { $0 }.joined(separator: " / ") }
    }

    func testTodayListsTodayAndTheWeekAddsTheFollowingDays() {
        let result = content(at: F.date(6, 10, 45))
        let today = result.filtered(by: .today)
        XCTAssertTrue(today.isShown)
        XCTAssertTrue(today.isTodayAvailable)
        XCTAssertEqual(today.effective, .today)
        XCTAssertEqual(filteredTitles(today), ["Today"])
        XCTAssertEqual(today.sections.flatMap(ids), ["ooo", "lunch", "val", "plan"])

        let week = result.filtered(by: .week)
        XCTAssertEqual(week.effective, .week)
        XCTAssertEqual(week.sections, result.sections, "7 Days is the whole list")
        XCTAssertEqual(Array(week.sections.prefix(today.sections.count)), today.sections, "switching keeps today's sections first; the week only adds day headings and the days after")
    }

    func testTodayKeepsWhatIsOnNow() {
        let state = content(at: F.date(6, 15, 56)).filtered(by: .today)
        XCTAssertEqual(filteredTitles(state), ["Now", "Today"])
        XCTAssertEqual(state.sections.flatMap(ids), ["val", "plan"])
    }

    // Evening: the old app's Today showed an empty list here. Today is dimmed and the week shows.
    func testNothingLeftTodayDimsTodayAndShowsTheWeek() {
        let state = content(at: F.date(5, 21, 30)).filtered(by: .today)
        XCTAssertTrue(state.isShown)
        XCTAssertFalse(state.isTodayAvailable)
        XCTAssertEqual(state.effective, .week)
        XCTAssertEqual(filteredTitles(state), ["Tomorrow / \(us("EEEdMMM", 6))", "Wednesday / \(us("dMMM", 7))", "Thursday / \(us("dMMM", 8))"])
    }

    func testDuringTheDaysLastMeetingTodayIsDimmed() {
        let result = content(at: F.date(6, 17, 30))
        guard case .now(let card) = result.hero else { return XCTFail("expected now, got \(result.hero)") }
        XCTAssertEqual(card.meeting.id, "val")
        let state = result.filtered(by: .today)
        XCTAssertFalse(state.isTodayAvailable)
        XCTAssertEqual(state.effective, .week)
    }

    func testOutOfOfficeRowsAloneDoNotMakeToday() {
        let away = Meeting(id: "away", title: "Out of office", start: F.date(6, 18), end: F.date(6, 23), isOutOfOffice: true)
        let state = content(at: F.date(6, 18, 30), meetings: [away, F.review]).filtered(by: .today)
        XCTAssertEqual(state.effective, .week, "a today made only of out-of-office rows would be an empty list in all but name")
        XCTAssertEqual(state.sections.flatMap(ids), ["away", "rev"], "the week still lists the out-of-office block")
    }

    func testTheSwitchHidesWhenNothingComesAfterToday() {
        let state = content(at: F.date(6, 10, 45), meetings: [F.lunch, F.workshop]).filtered(by: .week)
        XCTAssertFalse(state.isShown)
        XCTAssertEqual(state.sections.flatMap(ids), ["lunch", "val"])
        XCTAssertFalse(content(at: F.date(6, 20), meetings: []).filtered(by: .today).isShown)
    }

    func testDaySectionsAreLaterAndTodaysAreToday() {
        let result = content(at: F.date(6, 15, 56))
        XCTAssertEqual(result.sections.map(\.kind), [.now, .today, .later, .later])
    }

    // The card picks like the menu bar: the accepted call at 4:00 PM, not the Maybe block running since 3:00,
    // which is listed under Now (not "Also now", since it isn't the card's).
    func testTheCardPicksTheAcceptedMeetingOverAMaybeBlock() {
        var maybeWorkshop = F.workshop
        maybeWorkshop.myStatus = .tentative
        let result = content(at: F.date(6, 15, 13), meetings: [maybeWorkshop, F.planning])
        guard case .next(let card) = result.hero else { return XCTFail("expected next, got \(result.hero)") }
        XCTAssertEqual(card.meeting.id, "plan")
        XCTAssertEqual(result.sections.first?.title, "Now")
        XCTAssertEqual(result.sections.first.map(ids), ["val"])

        let duringTheCall = content(at: F.date(6, 16, 20), meetings: [maybeWorkshop, F.planning])
        guard case .now(let nowCard) = duringTheCall.hero else { return XCTFail("expected now, got \(duringTheCall.hero)") }
        XCTAssertEqual(nowCard.meeting.id, "plan")
        XCTAssertEqual(duringTheCall.sections.first?.title, "Also now")
        XCTAssertEqual(duringTheCall.sections.first.map(ids), ["val"])
    }

    // An accepted Workshop with a Maybe call inside it: the call still gets the starting-soon card (its alert
    // fires), but once it runs, the card goes back to the accepted Workshop.
    func testAMaybeCallInsideAnAcceptedMeetingGetsTheStartingSoonCardOnly() {
        var maybePlanning = F.planning
        maybePlanning.myStatus = .tentative
        let soon = content(at: F.date(6, 15, 56), meetings: [F.workshop, maybePlanning])
        guard case .startingSoon(let soonCard) = soon.hero else { return XCTFail("expected startingSoon, got \(soon.hero)") }
        XCTAssertEqual(soonCard.meeting.id, "plan")
        let running = content(at: F.date(6, 16, 20), meetings: [F.workshop, maybePlanning])
        guard case .now(let nowCard) = running.hero else { return XCTFail("expected now, got \(running.hero)") }
        XCTAssertEqual(nowCard.meeting.id, "val")
        XCTAssertEqual(running.sections.first.map(ids), ["plan"], "the Maybe call is listed under Also now")
    }

    // Today: "Now", then "Upcoming events" with today's rows and no day heading. 7 Days: the same "Upcoming
    // events", with each day (Today, Tomorrow, Thursday) as a heading under it, as the user asked.
    func testUpcomingEventsGroupsTheDaysUnderOneHeading() {
        let result = content(at: F.date(6, 15, 56))
        let today = result.filtered(by: .today)
        XCTAssertEqual(today.now?.title, "Now")
        XCTAssertEqual(today.now.map(ids), ["val"])
        XCTAssertEqual(today.upcoming.flatMap(ids), ["plan"])
        XCTAssertFalse(today.showsDayHeadings)

        let week = result.filtered(by: .week)
        XCTAssertEqual(week.now.map(ids), ["val"])
        XCTAssertEqual(week.upcoming.map(\.title), ["Today", "Tomorrow", "Thursday"])
        XCTAssertTrue(week.showsDayHeadings)

        let onlyToday = content(at: F.date(6, 10, 45), meetings: [F.lunch, F.workshop]).filtered(by: .week)
        XCTAssertFalse(onlyToday.showsDayHeadings, "nothing after today: a lone Today heading would say nothing")
        XCTAssertEqual(PanelFilterState.upcomingTitle, "Upcoming events")
    }

    // MARK: Dismissed events

    private func row(_ id: String, in content: PanelContent) -> PanelRow? {
        content.sections.lazy.flatMap(\.rows).first { $0.id == id }
    }

    // Later artboard, 10:45 AM: lunch is next. Dismissed, the card goes to the Workshop, and Today keeps lunch in
    // its place, marked, with its Directions button.
    func testADismissedNextMeetingGivesTheCardToTheOneAfter() {
        let result = content(at: F.date(6, 10, 45), dismissed: [F.lunch.id])
        guard case .next(let card) = result.hero else { return XCTFail("expected next, got \(result.hero)") }
        XCTAssertEqual(card.meeting.id, "val")
        XCTAssertEqual(card.label, "Next · in 4 h 15 min")
        XCTAssertEqual(result.sections.first.map(ids), ["ooo", "lunch", "val", "plan"])

        guard let lunch = row("lunch", in: result) else { return XCTFail("expected lunch's row") }
        XCTAssertEqual(lunch.dismissal, .dismissed)
        XCTAssertEqual(lunch.detail, .dismissed("Dismissed"), "in place of its location")
        XCTAssertEqual(lunch.action, .directions(LocationFormatter.directionsURL(to: F.lunch.location!)!), "joining is still allowed")
        XCTAssertFalse(lunch.isMuted, "muted is for out-of-office blocks")
    }

    // Busy artboard, 3:56 PM: Planning is starting soon. Dismissed, the Workshop in progress takes the card.
    func testADismissedStartingSoonMeetingGivesTheCardToTheOneInProgress() {
        let result = content(at: F.date(6, 15, 56), dismissed: [F.planning.id])
        guard case .now(let card) = result.hero else { return XCTFail("expected now, got \(result.hero)") }
        XCTAssertEqual(card.meeting.id, "val")
        XCTAssertEqual(card.label, "Now · 3 h 34 min left")
        XCTAssertEqual(titles(result), ["Today", "Tomorrow / \(us("EEEdMMM", 7))", "Thursday / \(us("dMMM", 8))"])
        XCTAssertEqual(result.sections.first.map(ids), ["plan"], "yet to start, it stays under Today")
        XCTAssertEqual(row("plan", in: result)?.detail, .dismissed("Dismissed"), "no overlap warning on a dismissed row")
        XCTAssertEqual(row("plan", in: result)?.action, .join(F.meet))
    }

    // Meeting artboard, 4:20 PM, in two meetings: the dismissed one is listed under Also now with its time left.
    func testADismissedMeetingInProgressIsListedUnderAlsoNow() {
        let undismissed = content(at: F.date(6, 16, 20))
        guard case .progress(_, let left)? = row("val", in: undismissed)?.detail else {
            return XCTFail("expected the Workshop's progress")
        }
        XCTAssertEqual(left, "3 h 10 min left")

        let result = content(at: F.date(6, 16, 20), dismissed: [F.workshop.id])
        guard case .now(let card) = result.hero else { return XCTFail("expected now, got \(result.hero)") }
        XCTAssertEqual(card.meeting.id, "plan")
        XCTAssertEqual(result.sections.first?.title, "Also now")
        XCTAssertEqual(result.sections.first.map(ids), ["val"])
        let workshop = row("val", in: result)
        XCTAssertEqual(workshop?.dismissal, .dismissed)
        XCTAssertEqual(workshop?.detail, .dismissed("Dismissed · \(left)"), "the time left as the progress line words it, without the bar")
        XCTAssertEqual(workshop?.action, .join(F.meet))

        // The card's own meeting dismissed: the other one in progress takes the card, and Also now lists the dismissed one.
        let other = content(at: F.date(6, 16, 20), dismissed: [F.planning.id])
        guard case .now(let otherCard) = other.hero else { return XCTFail("expected now, got \(other.hero)") }
        XCTAssertEqual(otherCard.meeting.id, "val")
        XCTAssertEqual(otherCard.label, "Now · 3 h 10 min left")
        XCTAssertEqual(other.sections.first?.title, "Also now")
        XCTAssertEqual(other.sections.first.map(ids), ["plan"])
        XCTAssertEqual(row("plan", in: other)?.detail, .dismissed("Dismissed · 40 min left"))
    }

    // 1:30 PM, at lunch: dismissed, the card shows the Workshop coming up, so lunch is listed under Now.
    func testADismissedMeetingInProgressIsListedUnderNowWhenTheCardIsNotNow() {
        let result = content(at: F.date(6, 13, 30), dismissed: [F.lunch.id])
        guard case .next(let card) = result.hero else { return XCTFail("expected next, got \(result.hero)") }
        XCTAssertEqual(card.meeting.id, "val")
        XCTAssertEqual(card.label, "Next · in 1 h 30 min")
        XCTAssertEqual(result.sections.first?.title, "Now")
        XCTAssertEqual(result.sections.first.map(ids), ["ooo", "lunch"])
        XCTAssertEqual(row("lunch", in: result)?.detail, .dismissed("Dismissed · 30 min left"))
        XCTAssertEqual(row("ooo", in: result)?.dismissal, nil)
    }

    func testNextUpSkipsDismissedMeetings() {
        func detail(_ dismissed: Set<String>) -> String? {
            guard case .nothingToday(let detail) = content(at: F.date(5, 21, 30), dismissed: dismissed).hero else { return nil }
            return F.squash(detail)
        }
        XCTAssertEqual(detail([]), "Next up tomorrow at 1:00 PM, in 15 h 30 min")
        XCTAssertEqual(detail([F.lunch.id]), "Next up tomorrow at 3:00 PM, in 17 h 30 min")
        XCTAssertEqual(detail([F.lunch.id, F.workshop.id, F.planning.id]), "Next up Wednesday at 9:10 AM")
        XCTAssertEqual(detail(Set(F.alertable.map(\.id))), "Nothing in the next 7 days")
        XCTAssertEqual(content(at: F.date(5, 21, 30), dismissed: Set(F.alertable.map(\.id))).sections.flatMap(ids),
                       content(at: F.date(5, 21, 30)).sections.flatMap(ids), "everything dismissed is still listed")
    }

    // The store passes alertable meetings without the dismissed ones; any left in are dropped all the same.
    func testDismissedMeetingsLeftInAlertableNeverTakeTheCard() {
        let result = content(at: F.date(6, 10, 45), alertable: F.alertable, dismissed: [F.lunch.id])
        XCTAssertEqual(result.hero.card?.meeting.id, "val")
        XCTAssertEqual(row("lunch", in: result)?.dismissal, .dismissed)
    }

    // Dismiss follows what alerts: a Show and alert meeting offers it, a dismissed one offers Restore, and one
    // that never alerts (Show in the list only, out-of-office blocks by default) offers neither, even with a
    // stored entry from before its choice changed.
    func testRowsOfferDismissOnlyForMeetingsThatMayAlert() {
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
        XCTAssertEqual(dismissals, [
            "ooo": nil, "focus": nil, "lunch": .dismissed, "val": .dismissable, "plan": .dismissable,
            "rev": .dismissable, "one": .dismissable, "road": .dismissable, "thu": .dismissable,
        ])
        XCTAssertNil(row("focus", in: listOnly)?.detail, "a list-only event isn't shown as dismissed")
        XCTAssertEqual(row("lunch", in: listOnly)?.detail, .dismissed("Dismissed"))

        let showAndAlert = panel(withoutParticipants: .showAndAlert)
        XCTAssertEqual(row("focus", in: showAndAlert)?.dismissal, .dismissed, "back to Show and alert, it's dismissed again")
        XCTAssertEqual(row("focus", in: showAndAlert)?.detail, .dismissed("Dismissed"))

        // An out-of-office block set to Show and alert can take the card, so its row offers Dismiss too (and Restore),
        // while staying muted.
        let outOfOffice = panel(withoutParticipants: .listOnly, outOfOffice: .showAndAlert)
        XCTAssertEqual(row("ooo", in: outOfOffice)?.dismissal, .dismissable)
        XCTAssertEqual(row("ooo", in: outOfOffice)?.isMuted, true)
        XCTAssertNil(row("ooo", in: outOfOffice)?.action)
        let dismissedBlock = content(at: F.date(5, 21, 30), alertable: F.week, dismissed: [F.outOfOffice.id])
        XCTAssertEqual(row("ooo", in: dismissedBlock)?.dismissal, .dismissed)
        XCTAssertEqual(row("ooo", in: dismissedBlock)?.detail, .dismissed("Dismissed"))
    }

    // A dismissed meeting clashes with nothing, either way round, on the rows and on the card.
    func testOverlapsIgnoreDismissedMeetings() {
        XCTAssertEqual(row("plan", in: content(at: F.date(5, 21, 30)))?.detail, .overlap("Overlaps Workshop"))
        XCTAssertNil(row("plan", in: content(at: F.date(5, 21, 30), dismissed: [F.workshop.id]))?.detail,
                     "the dismissed Workshop no longer clashes with Planning")
        let planningDismissed = content(at: F.date(5, 21, 30), dismissed: [F.planning.id])
        XCTAssertEqual(row("plan", in: planningDismissed)?.detail, .dismissed("Dismissed"))
        XCTAssertNil(row("val", in: planningDismissed)?.detail)

        // 3:56 PM: Planning's card warns about the Workshop until the Workshop is dismissed.
        let soon = content(at: F.date(6, 15, 56), dismissed: [F.workshop.id])
        guard case .startingSoon(let card) = soon.hero else { return XCTFail("expected startingSoon, got \(soon.hero)") }
        XCTAssertEqual(card.meeting.id, "plan")
        XCTAssertNil(card.overlap)
        XCTAssertEqual(soon.sections.first?.title, "Now")
        XCTAssertEqual(soon.sections.first.map(ids), ["val"])
        XCTAssertEqual(row("val", in: soon)?.detail, .dismissed("Dismissed · 3 h 34 min left"))

        // Of two meetings running when a third starts, a dismissed one is skipped and the other one named.
        let shortEarlier = Meeting(id: "c", title: "Short", start: F.date(6, 8, 30), end: F.date(6, 9, 15))
        let longEarlier = Meeting(id: "d", title: "Long", start: F.date(6, 8), end: F.date(6, 12))
        let late = Meeting(id: "e", title: "Late", start: F.date(6, 9, 10), end: F.date(6, 9, 40))
        let meetings = [shortEarlier, longEarlier, late]
        XCTAssertEqual(row("e", in: content(at: F.date(6, 7), meetings: meetings))?.detail, .overlap("Overlaps Long"))
        XCTAssertEqual(row("e", in: content(at: F.date(6, 7), meetings: meetings, dismissed: ["d"]))?.detail, .overlap("Overlaps Short"))
        guard case .next(let lateCard) = content(at: F.date(6, 9), meetings: [longEarlier, late], dismissed: ["d"]).hero else {
            return XCTFail("expected the late meeting's card")
        }
        XCTAssertNil(lateCard.overlap, "the card's line ignores the dismissed meeting too")
    }

    // 2:40 PM: the Workshop and Planning are all that's left today. Both dismissed, they're still on, so Today stays
    // available and lists them, while the card has nothing left today.
    func testTodayStaysAvailableWithOnlyDismissedMeetingsLeft() {
        let result = content(at: F.date(6, 14, 40), dismissed: [F.workshop.id, F.planning.id])
        guard case .nothingToday(let detail) = result.hero else { return XCTFail("expected nothingToday, got \(result.hero)") }
        XCTAssertEqual(F.squash(detail), "Next up tomorrow at 9:10 AM, in 18 h 30 min")
        let today = result.filtered(by: .today)
        XCTAssertTrue(today.isTodayAvailable)
        XCTAssertEqual(today.effective, .today)
        XCTAssertEqual(filteredTitles(today), ["Today"])
        XCTAssertEqual(today.sections.flatMap(ids), ["val", "plan"])

        // 5:30 PM, the day's last meeting dismissed: it's under Now, and Today isn't dimmed (compare
        // testDuringTheDaysLastMeetingTodayIsDimmed).
        let evening = content(at: F.date(6, 17, 30), dismissed: [F.workshop.id])
        guard case .nothingToday = evening.hero else { return XCTFail("expected nothingToday, got \(evening.hero)") }
        let state = evening.filtered(by: .today)
        XCTAssertTrue(state.isTodayAvailable)
        XCTAssertEqual(filteredTitles(state), ["Now"])
        XCTAssertEqual(row("val", in: evening)?.detail, .dismissed("Dismissed · 2 h left"))
    }

    func testDismissCopy() {
        XCTAssertEqual(DismissCopy.dismissTitle, "Dismiss")
        XCTAssertEqual(DismissCopy.restoreTitle, "Restore")
        XCTAssertEqual(DismissCopy.dismissedTitle, "Dismissed")
        XCTAssertEqual(DismissCopy.dismissedDetail(left: nil), "Dismissed")
        XCTAssertEqual(DismissCopy.dismissedDetail(left: "34 min left"), "Dismissed · 34 min left")
        XCTAssertEqual(DismissCopy.dismissAccessibilityLabel(for: F.workshop), "Dismiss Workshop")
        XCTAssertEqual(DismissCopy.restoreAccessibilityLabel(for: F.workshop), "Restore Workshop")
        XCTAssertEqual(DismissCopy.rowDismissHelp,
                       "Dismiss: no full-screen alert, and it leaves the menu bar and the top card. It stays in this list until it ends.")
        XCTAssertEqual(DismissCopy.cardDismissHelp,
                       "Dismiss: no full-screen alert, and it leaves the menu bar and this card. It stays in the list until it ends.")
        XCTAssertEqual(DismissCopy.restoreHelp, "Restore: its full-screen alert and the menu bar come back.")
        for help in [DismissCopy.rowDismissHelp, DismissCopy.cardDismissHelp, DismissCopy.restoreHelp] {
            XCTAssertFalse(help.contains("Don’t") || help.contains("Don't"), help)
        }
    }
}
