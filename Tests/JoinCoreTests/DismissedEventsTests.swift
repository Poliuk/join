import XCTest
@testable import JoinCore

final class DismissedEventsTests: XCTestCase {
    typealias F = MenuBarFixtures

    func testDismissAndRestore() {
        let none = DismissedEvents()
        XCTAssertTrue(none.isEmpty)
        XCTAssertFalse(none.contains(F.workshop.id))

        let dismissed = none.dismissing(F.workshop)
        XCTAssertFalse(dismissed.isEmpty)
        XCTAssertTrue(dismissed.contains(F.workshop.id))
        XCTAssertFalse(dismissed.contains(F.planning.id))
        XCTAssertEqual(dismissed.ends, [F.workshop.id: F.workshop.end], "kept until the occurrence ends")
        XCTAssertEqual(dismissed.ids, [F.workshop.id])
        XCTAssertEqual(dismissed.dismissing(F.workshop), dismissed, "dismissing twice changes nothing")

        let both = dismissed.dismissing(F.planning)
        XCTAssertEqual(both.ids, [F.workshop.id, F.planning.id])
        XCTAssertEqual(both.restoring(F.planning.id), dismissed)
        XCTAssertEqual(dismissed.restoring(F.workshop.id), none)
        XCTAssertEqual(dismissed.restoring("unknown"), dismissed, "restoring what isn't dismissed changes nothing")
    }

    // A recurring event shares its event identifier; each occurrence has its own id, and so does an
    // occurrence moved to another start.
    func testOnlyTheDismissedOccurrenceIsDismissed() {
        let monday = Meeting(id: Meeting.occurrenceID(eventIdentifier: "standup", start: F.date(5, 9)), title: "Standup", start: F.date(5, 9), end: F.date(5, 9, 15))
        let tuesday = Meeting(id: Meeting.occurrenceID(eventIdentifier: "standup", start: F.date(6, 9)), title: "Standup", start: F.date(6, 9), end: F.date(6, 9, 15))
        let dismissed = DismissedEvents().dismissing(monday)
        XCTAssertTrue(dismissed.contains(monday.id))
        XCTAssertFalse(dismissed.contains(tuesday.id))
        XCTAssertFalse(dismissed.contains(Meeting.occurrenceID(eventIdentifier: "standup", start: F.date(5, 10))),
                       "moved to 10:00, it's a new occurrence")
    }

    func testPruningDropsEventsThatHaveEnded() {
        let dismissed = DismissedEvents().dismissing(F.lunch).dismissing(F.workshop)
        XCTAssertEqual(dismissed.pruned(at: F.date(6, 13, 30), meetings: [F.lunch, F.workshop]), dismissed, "both still on or to come")
        XCTAssertEqual(dismissed.pruned(at: F.date(6, 14), meetings: [F.lunch, F.workshop]).ids, [F.workshop.id], "lunch ended at 2:00 PM")
        XCTAssertTrue(dismissed.pruned(at: F.date(6, 19, 30), meetings: [F.lunch, F.workshop]).isEmpty)
        XCTAssertTrue(DismissedEvents().pruned(at: F.date(6, 12), meetings: F.week).isEmpty)
    }

    // An event missing from the meetings (its calendar unchecked, a fetch that failed) is kept until its stored end.
    func testPruningKeepsAnUnknownEventUntilItsStoredEnd() {
        let dismissed = DismissedEvents().dismissing(F.workshop)
        XCTAssertEqual(dismissed.pruned(at: F.date(6, 16), meetings: []), dismissed)
        XCTAssertEqual(dismissed.pruned(at: F.date(6, 19, 29), meetings: [F.lunch]), dismissed)
        XCTAssertTrue(dismissed.pruned(at: F.date(6, 19, 30), meetings: []).isEmpty)
        XCTAssertTrue(dismissed.pruned(at: F.date(7, 9), meetings: [F.lunch]).isEmpty)
    }

    // Workshop, dismissed while it ran until 7:30 PM, now runs until 8:30 PM: it stays dismissed to the new end
    // rather than coming back at 7:30.
    func testPruningFollowsAnEventExtendedAfterItWasDismissed() {
        let dismissed = DismissedEvents().dismissing(F.workshop)
        var extended = F.workshop
        extended.end = F.date(6, 20, 30)

        let atOldEnd = dismissed.pruned(at: F.date(6, 19, 45), meetings: [extended])
        XCTAssertTrue(atOldEnd.contains(F.workshop.id))
        XCTAssertEqual(atOldEnd.ends[F.workshop.id], extended.end, "the stored end follows the event")

        let earlier = dismissed.pruned(at: F.date(6, 16), meetings: [extended])
        XCTAssertEqual(earlier.ends[F.workshop.id], extended.end, "updated before the old end too")
        XCTAssertEqual(earlier.pruned(at: F.date(6, 19, 45), meetings: []), earlier, "and kept if it then goes missing")

        XCTAssertTrue(atOldEnd.pruned(at: F.date(6, 20, 30), meetings: [extended]).isEmpty)
    }

    func testPruningFollowsAnEventShortenedAfterItWasDismissed() {
        let dismissed = DismissedEvents().dismissing(F.workshop)
        var shortened = F.workshop
        shortened.end = F.date(6, 17)
        XCTAssertEqual(dismissed.pruned(at: F.date(6, 16), meetings: [shortened]).ends[F.workshop.id], shortened.end)
        XCTAssertTrue(dismissed.pruned(at: F.date(6, 17, 30), meetings: [shortened]).isEmpty, "over at its new end")
    }

    func testJSONRoundTrip() throws {
        let dismissed = DismissedEvents().dismissing(F.workshop).dismissing(F.review)
        let data = try JSONEncoder().encode(dismissed)
        XCTAssertEqual(try JSONDecoder().decode(DismissedEvents.self, from: data), dismissed)
        XCTAssertEqual(try JSONDecoder().decode(DismissedEvents.self, from: JSONEncoder().encode(DismissedEvents())), DismissedEvents())

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), [F.workshop.id, F.review.id], "a plain object of occurrence id → end")
    }

    func testUnreadableJSONDoesNotDecode() {
        for json in [#"not json"#, #"["val"]"#, #"{"val": "tonight"}"#, #"{"val": null}"#, #"3"#] {
            XCTAssertNil(try? JSONDecoder().decode(DismissedEvents.self, from: Data(json.utf8)), json)
        }
    }
}
