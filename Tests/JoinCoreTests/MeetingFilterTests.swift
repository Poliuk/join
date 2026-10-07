import XCTest
@testable import JoinCore

final class MeetingFilterTests: XCTestCase {
    func testAllDayEventsAreExcluded() {
        XCTAssertFalse(MeetingFilter.shouldInclude(isAllDay: true, isCanceled: false, myStatus: .accepted))
    }

    func testCanceledEventsAreExcluded() {
        XCTAssertFalse(MeetingFilter.shouldInclude(isAllDay: false, isCanceled: true, myStatus: .accepted))
    }

    func testDeclinedEventsAreExcluded() {
        XCTAssertFalse(MeetingFilter.shouldInclude(isAllDay: false, isCanceled: false, myStatus: .declined))
    }

    func testTentativeAndUnknownAreIncluded() {
        XCTAssertTrue(MeetingFilter.shouldInclude(isAllDay: false, isCanceled: false, myStatus: .tentative))
        XCTAssertTrue(MeetingFilter.shouldInclude(isAllDay: false, isCanceled: false, myStatus: .unknown))
    }

    // MARK: Events choices

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func meeting(
        _ id: String,
        participants: Bool,
        status: ParticipationStatus = .accepted,
        outOfOffice: Bool = false
    ) -> Meeting {
        Meeting(
            id: id, title: id, start: start, end: start.addingTimeInterval(3600),
            myStatus: status, hasParticipants: participants, isOutOfOffice: outOfOffice
        )
    }

    /// One event of each kind: an ordinary one, one with no participants, an out-of-office one, and both.
    private var kinds: [Meeting] {
        [
            meeting("call", participants: true),
            meeting("focus", participants: false),
            meeting("ooo", participants: true, outOfOffice: true),
            meeting("ooo-solo", participants: false, outOfOffice: true),
        ]
    }

    func testMeetingsHaveParticipantsUnlessToldOtherwise() {
        XCTAssertTrue(Meeting(id: "call", title: "Call", start: start, end: start.addingTimeInterval(1800)).hasParticipants)
        XCTAssertFalse(meeting("focus", participants: false).hasParticipants)
    }

    func testEveryCombinationOfChoices() {
        let all = ["call", "focus", "ooo", "ooo-solo"]
        // (no participants, out of office) → (visible, alertable)
        let cases: [(EventVisibility, EventVisibility, [String], [String])] = [
            (.showAndAlert, .showAndAlert, all, all),
            (.showAndAlert, .listOnly, all, ["call", "focus"]),
            (.showAndAlert, .exclude, ["call", "focus"], ["call", "focus"]),
            (.listOnly, .showAndAlert, all, ["call", "ooo"]),
            (.listOnly, .listOnly, all, ["call"]),
            (.listOnly, .exclude, ["call", "focus"], ["call"]),
            (.exclude, .showAndAlert, ["call", "ooo"], ["call", "ooo"]),
            (.exclude, .listOnly, ["call", "ooo"], ["call"]),
            (.exclude, .exclude, ["call"], ["call"]),
        ]
        XCTAssertEqual(cases.count, EventVisibility.allCases.count * EventVisibility.allCases.count)
        for (withoutParticipants, outOfOffice, visible, alertable) in cases {
            let label = "\(withoutParticipants), \(outOfOffice)"
            XCTAssertEqual(
                MeetingFilter.visible(kinds, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice).map(\.id),
                visible, label
            )
            XCTAssertEqual(
                MeetingFilter.alertable(kinds, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice).map(\.id),
                alertable, label
            )
        }
    }

    func testAnEventOfBothKindsGetsTheChoiceThatShowsLess() {
        let both = meeting("ooo-solo", participants: false, outOfOffice: true)
        let cases: [(EventVisibility, EventVisibility, EventVisibility)] = [
            (.showAndAlert, .showAndAlert, .showAndAlert),
            (.showAndAlert, .listOnly, .listOnly),
            (.showAndAlert, .exclude, .exclude),
            (.listOnly, .showAndAlert, .listOnly),
            (.listOnly, .listOnly, .listOnly),
            (.listOnly, .exclude, .exclude),
            (.exclude, .showAndAlert, .exclude),
            (.exclude, .listOnly, .exclude),
            (.exclude, .exclude, .exclude),
        ]
        for (withoutParticipants, outOfOffice, expected) in cases {
            XCTAssertEqual(
                MeetingFilter.visibility(of: both, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice),
                expected, "\(withoutParticipants), \(outOfOffice)"
            )
        }
    }

    func testEachKindGetsItsOwnChoiceAndOrdinaryEventsAlwaysShowAndAlert() {
        for withoutParticipants in EventVisibility.allCases {
            for outOfOffice in EventVisibility.allCases {
                func choice(_ meeting: Meeting) -> EventVisibility {
                    MeetingFilter.visibility(of: meeting, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice)
                }
                let label = "\(withoutParticipants), \(outOfOffice)"
                XCTAssertEqual(choice(kinds[0]), .showAndAlert, label)
                XCTAssertEqual(choice(kinds[1]), withoutParticipants, label)
                XCTAssertEqual(choice(kinds[2]), outOfOffice, label)
            }
        }
    }

    func testFilteringKeepsTheOrder() {
        let meetings = [
            meeting("standup", participants: true),
            meeting("focus", participants: false),
            meeting("review", participants: true),
            meeting("away", participants: true, outOfOffice: true),
            meeting("reminder", participants: false),
        ]
        XCTAssertEqual(
            MeetingFilter.visible(meetings, eventsWithoutParticipants: .exclude, outOfOfficeEvents: .listOnly).map(\.id),
            ["standup", "review", "away"]
        )
        XCTAssertEqual(
            MeetingFilter.alertable(meetings, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .listOnly).map(\.id),
            ["standup", "focus", "review", "reminder"]
        )
        XCTAssertEqual(MeetingFilter.visible([], eventsWithoutParticipants: .exclude, outOfOfficeEvents: .exclude), [])
        XCTAssertEqual(MeetingFilter.alertable([], eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert), [])
    }

    func testAlertableIsAlwaysWithinVisible() {
        for withoutParticipants in EventVisibility.allCases {
            for outOfOffice in EventVisibility.allCases {
                let visible = MeetingFilter.visible(kinds, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice)
                let alertable = MeetingFilter.alertable(kinds, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice)
                XCTAssertTrue(Set(alertable.map(\.id)).isSubset(of: visible.map(\.id)), "\(withoutParticipants), \(outOfOffice)")
                XCTAssertEqual(
                    MeetingFilter.alertable(visible, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice),
                    alertable, "the same whether given every meeting or the visible ones"
                )
            }
        }
    }

    func testYourAnswerDoesNotChangeTheChoice() {
        for status in [ParticipationStatus.accepted, .tentative, .unknown] {
            let meetings = [meeting("call", participants: true, status: status), meeting("hold", participants: false, status: status)]
            XCTAssertEqual(
                MeetingFilter.visible(meetings, eventsWithoutParticipants: .exclude, outOfOfficeEvents: .listOnly).map(\.id),
                ["call"], "\(status)"
            )
            XCTAssertEqual(
                MeetingFilter.alertable(meetings, eventsWithoutParticipants: .listOnly, outOfOfficeEvents: .listOnly).map(\.id),
                ["call"], "\(status)"
            )
            XCTAssertEqual(
                MeetingFilter.alertable(meetings, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .listOnly).map(\.id),
                ["call", "hold"], "\(status)"
            )
        }
        // Declined events never reach the list, so no choice can bring them back either.
        XCTAssertFalse(MeetingFilter.shouldInclude(isAllDay: false, isCanceled: false, myStatus: .declined))
    }

    func testOccurrenceIDIncludesStart() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(Meeting.occurrenceID(eventIdentifier: "evt", start: start), "evt@1800000000")
        XCTAssertNotEqual(
            Meeting.occurrenceID(eventIdentifier: "evt", start: start),
            Meeting.occurrenceID(eventIdentifier: "evt", start: start.addingTimeInterval(86400))
        )
    }
}
