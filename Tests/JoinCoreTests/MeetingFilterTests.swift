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

    // MARK: Dismissed events

    func testDismissedMeetingsAreNotAlertableButStayVisible() {
        let dismissed = DismissedEvents().dismissing(kinds[0])
        XCTAssertEqual(
            MeetingFilter.alertable(kinds, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert, dismissed: dismissed).map(\.id),
            ["focus", "ooo", "ooo-solo"]
        )
        XCTAssertEqual(
            MeetingFilter.alertable(kinds, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert, dismissed: DismissedEvents()),
            MeetingFilter.alertable(kinds, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert),
            "nothing dismissed by default"
        )
        XCTAssertEqual(
            MeetingFilter.visible(kinds, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert).map(\.id),
            ["call", "focus", "ooo", "ooo-solo"], "the lists keep a dismissed event"
        )
    }

    // Only an event that could alert is dismissed: one whose choice became Show in the list only (or Exclude)
    // after it was dismissed is shown according to the new choice.
    func testDismissedIDsAreTheShowAndAlertOnesOnly() {
        let dismissed = DismissedEvents().dismissing(kinds[0]).dismissing(kinds[1]).dismissing(kinds[2])
        func ids(_ withoutParticipants: EventVisibility, _ outOfOffice: EventVisibility) -> Set<String> {
            MeetingFilter.dismissedIDs(kinds, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice, dismissed: dismissed)
        }
        XCTAssertEqual(ids(.showAndAlert, .showAndAlert), ["call", "focus", "ooo"])
        XCTAssertEqual(ids(.showAndAlert, .listOnly), ["call", "focus"])
        XCTAssertEqual(ids(.listOnly, .listOnly), ["call"])
        XCTAssertEqual(ids(.exclude, .exclude), ["call"])
        XCTAssertEqual(
            MeetingFilter.dismissedIDs(kinds, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert, dismissed: DismissedEvents()),
            []
        )
        XCTAssertEqual(
            MeetingFilter.dismissedIDs([], eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert, dismissed: dismissed),
            [], "an entry with no meeting (ended, or its calendar unchecked) shows nowhere"
        )

        for withoutParticipants in EventVisibility.allCases {
            for outOfOffice in EventVisibility.allCases {
                let label = "\(withoutParticipants), \(outOfOffice)"
                let all = MeetingFilter.alertable(kinds, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice)
                let alertable = MeetingFilter.alertable(kinds, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice, dismissed: dismissed)
                XCTAssertEqual(
                    Set(alertable.map(\.id)).union(ids(withoutParticipants, outOfOffice)), Set(all.map(\.id)),
                    "the Show and alert events are split between alertable and dismissed: \(label)"
                )
                XCTAssertTrue(Set(alertable.map(\.id)).isDisjoint(with: ids(withoutParticipants, outOfOffice)), label)
            }
        }
    }

    // A repeating event's occurrences: alertable and dismissedIDs ask `DismissedEvents.isDismissed`, so All Future
    // Events, and an occurrence restored inside it, count like an occurrence dismissed on its own.
    func testDismissedSeriesAreLeftOutOfAlertable() {
        func standup(_ day: Int, participants: Bool = true) -> Meeting {
            let date = start.addingTimeInterval(Double(day) * 86400)
            return Meeting(id: Meeting.occurrenceID(eventIdentifier: "standup", start: date), title: "Standup", start: date,
                           end: date.addingTimeInterval(900), hasParticipants: participants, seriesID: "standup")
        }
        let week = (0..<5).map { standup($0) }
        let others = [meeting("call", participants: true)]
        let stored = DismissedEvents().dismissing(week[2], scope: .allFutureEvents).restoring(week[3])
        let ids = { (meetings: [Meeting]) in meetings.map(\.id) }

        XCTAssertEqual(
            MeetingFilter.alertable(week + others, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert, dismissed: stored).map(\.id),
            ids([week[0], week[1], week[3]]) + ["call"]
        )
        XCTAssertEqual(
            MeetingFilter.dismissedIDs(week + others, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert, dismissed: stored),
            Set(ids([week[2], week[4]]))
        )
        XCTAssertEqual(
            MeetingFilter.visible(week + others, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert).count,
            6, "the lists keep them"
        )

        // An occurrence that can't alert (here, no one else on it, and that kind on Show in the list only) isn't
        // shown as dismissed, even inside the rule.
        let solo = standup(4, participants: false)
        XCTAssertTrue(stored.isDismissed(solo))
        XCTAssertEqual(
            MeetingFilter.dismissedIDs([solo], eventsWithoutParticipants: .listOnly, outOfOfficeEvents: .showAndAlert, dismissed: stored),
            []
        )

        // Of those, the ones whose Restore asks: dismissed with their series, not one dismissed on its own.
        let alsoAlone = stored.dismissing(week[0])
        XCTAssertEqual(
            MeetingFilter.dismissedBySeriesIDs(week + others, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert, dismissed: alsoAlone),
            Set(ids([week[2], week[4]])), "Monday's was dismissed on its own"
        )
        XCTAssertEqual(
            MeetingFilter.dismissedBySeriesIDs([solo], eventsWithoutParticipants: .listOnly, outOfOfficeEvents: .showAndAlert, dismissed: stored),
            [], "not one that can't alert"
        )
        XCTAssertEqual(
            MeetingFilter.dismissedBySeriesIDs(week, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert,
                                               dismissed: DismissedEvents().dismissing(week[1])),
            [], "no series rule, nothing asks"
        )
    }

    func testRepeatingEventsHaveASeries() {
        XCTAssertFalse(meeting("call", participants: true).isRepeating)
        let occurrence = Meeting(id: "standup@1", title: "Standup", start: start, end: start, seriesID: "standup")
        XCTAssertTrue(occurrence.isRepeating)
        XCTAssertEqual(occurrence.seriesID, "standup")
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
