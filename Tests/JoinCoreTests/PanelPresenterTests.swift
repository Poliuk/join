import XCTest
@testable import JoinCore

final class PanelPresenterTests: XCTestCase {
    typealias F = MenuBarFixtures

    private func content(at now: Date, meetings: [Meeting] = F.week, alertable: [Meeting]? = nil, locale: Locale = F.us) -> PanelContent {
        PanelPresenter.content(meetings: meetings, alertable: alertable ?? meetings.filter { !$0.isOutOfOffice }, now: now, calendar: F.calendar, locale: locale)
    }

    private func titles(_ content: PanelContent) -> [String] {
        content.sections.map { [$0.title, F.squash($0.subtitle)].compactMap { $0 }.joined(separator: " / ") }
    }

    private func ids(_ section: PanelSection) -> [String] {
        section.rows.map(\.meeting.id)
    }

    // Main artboard: Monday 9:30 PM, nothing left today.
    func testNothingLeftToday() {
        let result = content(at: F.date(5, 21, 30))
        guard case .nothingToday(let detail) = result.hero else { return XCTFail("expected nothingToday, got \(result.hero)") }
        XCTAssertEqual(F.squash(detail), "Next up tomorrow at 1:00 PM, in 15 h 30 min")
        XCTAssertEqual(titles(result), ["Tomorrow / Tue, Oct 6", "Wednesday / Oct 7", "Thursday / Oct 8"])
        XCTAssertEqual(ids(result.sections[0]), ["ooo", "lunch", "val", "plan"])
        XCTAssertEqual(ids(result.sections[1]), ["rev", "one", "road"])
    }

    func testDayHeadingsAreLocalized() {
        let result = content(at: F.date(5, 21, 30), locale: F.gb)
        XCTAssertEqual(titles(result), ["Tomorrow / Tue 6 Oct", "Wednesday / 7 Oct", "Thursday / 8 Oct"])
    }

    func testRowsFromTheDesign() {
        let tuesday = content(at: F.date(5, 21, 30)).sections[0].rows

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

        XCTAssertEqual(titles(result), ["Later today", "Tomorrow / Wed, Oct 7", "Thursday / Oct 8"])
        XCTAssertEqual(ids(result.sections[0]), ["ooo", "val", "plan"], "the hero meeting isn't repeated")
    }

    // Busy artboard: Tuesday 3:56 PM, a meeting starts in 4 minutes while another one runs.
    func testStartingSoonWinsOverAMeetingInProgress() {
        let result = content(at: F.date(6, 15, 56))
        guard case .startingSoon(let card) = result.hero else { return XCTFail("expected startingSoon, got \(result.hero)") }
        XCTAssertEqual(card.meeting.id, "plan")
        XCTAssertEqual(card.label, "Starts in 4 min")
        XCTAssertEqual(F.squash(card.overlap), "Overlaps Workshop, which runs until 7:30 PM")
        XCTAssertEqual(card.action, .join(F.meet))

        XCTAssertEqual(titles(result), ["Now", "Tomorrow / Wed, Oct 7", "Thursday / Oct 8"])
        XCTAssertEqual(ids(result.sections[0]), ["val"])
        guard case .progress(let elapsed, let left) = result.sections[0].rows[0].detail else {
            return XCTFail("expected progress, got \(String(describing: result.sections[0].rows[0].detail))")
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

        XCTAssertEqual(titles(result), ["Also now", "Tomorrow / Wed, Oct 7", "Thursday / Oct 8"])
        guard case .progress(let elapsed, let left) = result.sections[0].rows[0].detail else {
            return XCTFail("expected progress, got \(String(describing: result.sections[0].rows[0].detail))")
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
        XCTAssertEqual(ids(result.sections[0]), ["ooo"])
        XCTAssertTrue(result.sections[0].rows[0].isMuted)
        XCTAssertNil(result.sections[0].rows[0].detail)

        let afterLunch = content(at: F.date(6, 14, 10))
        guard case .next = afterLunch.hero else { return XCTFail("expected next, got \(afterLunch.hero)") }
        XCTAssertEqual(titles(afterLunch).prefix(2), ["Now", "Later today"])
    }

    func testNextUpBeyondTomorrowLeavesOutTheCountdown() {
        let result = content(at: F.date(6, 20), meetings: [F.thursday])
        guard case .nothingToday(let detail) = result.hero else { return XCTFail("expected nothingToday, got \(result.hero)") }
        XCTAssertEqual(F.squash(detail), "Next up Thursday at 10:00 AM")
        let empty = content(at: F.date(6, 20), meetings: [])
        XCTAssertEqual(empty.hero, .nothingToday(detail: "Nothing in the next 7 days"))
        XCTAssertTrue(empty.sections.isEmpty)
    }

    func testNextUpAWeekAheadShowsTheDate() {
        func detail(_ meetings: [Meeting], locale: Locale = F.us) -> String? {
            guard case .nothingToday(let detail) = content(at: F.date(5, 10), meetings: meetings, locale: locale).hero else { return nil }
            return F.squash(detail)
        }
        XCTAssertEqual(detail([F.nextMonday]), "Next up Mon, Oct 12 at 9:00 AM")
        XCTAssertEqual(detail([F.nextMonday], locale: F.gb), "Next up Mon 12 Oct at 09:00")
        XCTAssertEqual(detail([F.sunday]), "Next up Sunday at 9:00 AM")
        XCTAssertEqual(titles(content(at: F.date(5, 10), meetings: [F.nextMonday])), ["Monday / Oct 12"])
    }

    func testLocationsThatAreNotPlaces() {
        let hybrid = Meeting(id: "h", title: "Hybrid", start: F.date(6, 9), end: F.date(6, 10), location: "Sala Retiro; Microsoft Teams Meeting")
        let bareLink = Meeting(id: "l", title: "Link", start: F.date(6, 11), end: F.date(6, 12), location: "meet.google.com/abc-defg-hij")
        let dialIn = Meeting(id: "p", title: "Call", start: F.date(6, 13), end: F.date(6, 14), location: "Tel: +34 600 123 456")
        let rows = content(at: F.date(5, 21), meetings: [hybrid, bareLink, dialIn]).sections[0].rows

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
}
