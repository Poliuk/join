import Foundation
import Testing
@testable import JoinCore

struct MeetingFilterTests {
    @Test func allDayEventsAreExcluded() {
        #expect(!MeetingFilter.shouldInclude(isAllDay: true, isCanceled: false, myStatus: .accepted))
    }

    @Test func canceledEventsAreExcluded() {
        #expect(!MeetingFilter.shouldInclude(isAllDay: false, isCanceled: true, myStatus: .accepted))
    }

    @Test func declinedEventsAreExcluded() {
        #expect(!MeetingFilter.shouldInclude(isAllDay: false, isCanceled: false, myStatus: .declined))
    }

    @Test func tentativeAndUnknownAreIncluded() {
        #expect(MeetingFilter.shouldInclude(isAllDay: false, isCanceled: false, myStatus: .tentative))
        #expect(MeetingFilter.shouldInclude(isAllDay: false, isCanceled: false, myStatus: .unknown))
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

    @Test func meetingsHaveParticipantsUnlessToldOtherwise() {
        #expect(Meeting(id: "call", title: "Call", start: start, end: start.addingTimeInterval(1800)).hasParticipants)
        #expect(!meeting("focus", participants: false).hasParticipants)
    }

    @Test func everyCombinationOfChoices() {
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
        #expect(cases.count == EventVisibility.allCases.count * EventVisibility.allCases.count)
        for (withoutParticipants, outOfOffice, visible, alertable) in cases {
            let label = "\(withoutParticipants), \(outOfOffice)"
            #expect(
                MeetingFilter.visible(kinds, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice).map(\.id)
                    == visible, "\(label)"
            )
            #expect(
                MeetingFilter.alertable(kinds, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice).map(\.id)
                    == alertable, "\(label)"
            )
        }
    }

    @Test func anEventOfBothKindsGetsTheChoiceThatShowsLess() {
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
            #expect(
                MeetingFilter.visibility(of: both, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice)
                    == expected, "\(withoutParticipants), \(outOfOffice)"
            )
        }
    }

    @Test func eachKindGetsItsOwnChoiceAndOrdinaryEventsAlwaysShowAndAlert() {
        for withoutParticipants in EventVisibility.allCases {
            for outOfOffice in EventVisibility.allCases {
                func choice(_ meeting: Meeting) -> EventVisibility {
                    MeetingFilter.visibility(of: meeting, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice)
                }
                let label = "\(withoutParticipants), \(outOfOffice)"
                #expect(choice(kinds[0]) == .showAndAlert, "\(label)")
                #expect(choice(kinds[1]) == withoutParticipants, "\(label)")
                #expect(choice(kinds[2]) == outOfOffice, "\(label)")
            }
        }
    }

    @Test func filteringKeepsTheOrder() {
        let meetings = [
            meeting("standup", participants: true),
            meeting("focus", participants: false),
            meeting("review", participants: true),
            meeting("away", participants: true, outOfOffice: true),
            meeting("reminder", participants: false),
        ]
        #expect(
            MeetingFilter.visible(meetings, eventsWithoutParticipants: .exclude, outOfOfficeEvents: .listOnly).map(\.id)
                == ["standup", "review", "away"]
        )
        #expect(
            MeetingFilter.alertable(meetings, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .listOnly).map(\.id)
                == ["standup", "focus", "review", "reminder"]
        )
        #expect(MeetingFilter.visible([], eventsWithoutParticipants: .exclude, outOfOfficeEvents: .exclude) == [])
        #expect(MeetingFilter.alertable([], eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert) == [])
    }

    @Test func alertableIsAlwaysWithinVisible() {
        for withoutParticipants in EventVisibility.allCases {
            for outOfOffice in EventVisibility.allCases {
                let visible = MeetingFilter.visible(kinds, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice)
                let alertable = MeetingFilter.alertable(kinds, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice)
                #expect(Set(alertable.map(\.id)).isSubset(of: visible.map(\.id)), "\(withoutParticipants), \(outOfOffice)")
                #expect(
                    MeetingFilter.alertable(visible, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice)
                        == alertable, "the same whether given every meeting or the visible ones"
                )
            }
        }
    }

    @Test func yourAnswerDoesNotChangeTheChoice() {
        for status in [ParticipationStatus.accepted, .tentative, .unknown] {
            let meetings = [meeting("call", participants: true, status: status), meeting("hold", participants: false, status: status)]
            #expect(
                MeetingFilter.visible(meetings, eventsWithoutParticipants: .exclude, outOfOfficeEvents: .listOnly).map(\.id)
                    == ["call"], "\(status)"
            )
            #expect(
                MeetingFilter.alertable(meetings, eventsWithoutParticipants: .listOnly, outOfOfficeEvents: .listOnly).map(\.id)
                    == ["call"], "\(status)"
            )
            #expect(
                MeetingFilter.alertable(meetings, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .listOnly).map(\.id)
                    == ["call", "hold"], "\(status)"
            )
        }
        // Declined events never reach the list, so no choice can bring them back either.
        #expect(!MeetingFilter.shouldInclude(isAllDay: false, isCanceled: false, myStatus: .declined))
    }

    // MARK: Dismissed events

    @Test func dismissedMeetingsAreNotAlertableButStayVisible() {
        let dismissed = DismissedEvents().dismissing(kinds[0])
        #expect(
            MeetingFilter.alertable(kinds, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert, dismissed: dismissed).map(\.id)
                == ["focus", "ooo", "ooo-solo"]
        )
        #expect(
            MeetingFilter.alertable(kinds, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert, dismissed: DismissedEvents())
                == MeetingFilter.alertable(kinds, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert),
            "nothing dismissed by default"
        )
        #expect(
            MeetingFilter.visible(kinds, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert).map(\.id)
                == ["call", "focus", "ooo", "ooo-solo"], "the lists keep a dismissed event"
        )
    }

    // Only an event that could alert is dismissed: one whose choice became Show in the list only (or Exclude)
    // after it was dismissed is shown according to the new choice.
    @Test func dismissedIDsAreTheShowAndAlertOnesOnly() {
        let dismissed = DismissedEvents().dismissing(kinds[0]).dismissing(kinds[1]).dismissing(kinds[2])
        func ids(_ withoutParticipants: EventVisibility, _ outOfOffice: EventVisibility) -> Set<String> {
            MeetingFilter.dismissedIDs(kinds, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice, dismissed: dismissed)
        }
        #expect(ids(.showAndAlert, .showAndAlert) == ["call", "focus", "ooo"])
        #expect(ids(.showAndAlert, .listOnly) == ["call", "focus"])
        #expect(ids(.listOnly, .listOnly) == ["call"])
        #expect(ids(.exclude, .exclude) == ["call"])
        #expect(
            MeetingFilter.dismissedIDs(kinds, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert, dismissed: DismissedEvents())
                == []
        )
        #expect(
            MeetingFilter.dismissedIDs([], eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert, dismissed: dismissed)
                == [], "an entry with no meeting (ended, or its calendar unchecked) shows nowhere"
        )

        for withoutParticipants in EventVisibility.allCases {
            for outOfOffice in EventVisibility.allCases {
                let label = "\(withoutParticipants), \(outOfOffice)"
                let all = MeetingFilter.alertable(kinds, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice)
                let alertable = MeetingFilter.alertable(kinds, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice, dismissed: dismissed)
                #expect(
                    Set(alertable.map(\.id)).union(ids(withoutParticipants, outOfOffice)) == Set(all.map(\.id)),
                    "the Show and alert events are split between alertable and dismissed: \(label)"
                )
                #expect(Set(alertable.map(\.id)).isDisjoint(with: ids(withoutParticipants, outOfOffice)), "\(label)")
            }
        }
    }

    // A repeating event's occurrences: alertable and dismissedIDs ask `DismissedEvents.isDismissed`, so All Future
    // Events, and an occurrence restored inside it, count like an occurrence dismissed on its own.
    @Test func dismissedSeriesAreLeftOutOfAlertable() {
        func standup(_ day: Int, participants: Bool = true) -> Meeting {
            let date = start.addingTimeInterval(Double(day) * 86400)
            return Meeting(id: Meeting.occurrenceID(eventIdentifier: "standup", start: date), title: "Standup", start: date,
                           end: date.addingTimeInterval(900), hasParticipants: participants, seriesID: "standup")
        }
        let week = (0..<5).map { standup($0) }
        let others = [meeting("call", participants: true)]
        let stored = DismissedEvents().dismissing(week[2], scope: .allFutureEvents).restoring(week[3])
        let ids = { (meetings: [Meeting]) in meetings.map(\.id) }

        #expect(
            MeetingFilter.alertable(week + others, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert, dismissed: stored).map(\.id)
                == ids([week[0], week[1], week[3]]) + ["call"]
        )
        #expect(
            MeetingFilter.dismissedIDs(week + others, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert, dismissed: stored)
                == Set(ids([week[2], week[4]]))
        )
        #expect(
            MeetingFilter.visible(week + others, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert).count
                == 6, "the lists keep them"
        )

        // An occurrence that can't alert (here, no one else on it, and that kind on Show in the list only) isn't
        // shown as dismissed, even inside the rule.
        let solo = standup(4, participants: false)
        #expect(stored.isDismissed(solo))
        #expect(
            MeetingFilter.dismissedIDs([solo], eventsWithoutParticipants: .listOnly, outOfOfficeEvents: .showAndAlert, dismissed: stored)
                == []
        )

        // Of those, the ones whose Restore asks: dismissed with their series, not one dismissed on its own.
        let alsoAlone = stored.dismissing(week[0])
        #expect(
            MeetingFilter.dismissedBySeriesIDs(week + others, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert, dismissed: alsoAlone)
                == Set(ids([week[2], week[4]])), "Monday's was dismissed on its own"
        )
        #expect(
            MeetingFilter.dismissedBySeriesIDs([solo], eventsWithoutParticipants: .listOnly, outOfOfficeEvents: .showAndAlert, dismissed: stored)
                == [], "not one that can't alert"
        )
        #expect(
            MeetingFilter.dismissedBySeriesIDs(week, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert,
                                               dismissed: DismissedEvents().dismissing(week[1]))
                == [], "no series rule, nothing asks"
        )
    }

    @Test func repeatingEventsHaveASeries() {
        #expect(!meeting("call", participants: true).isRepeating)
        let occurrence = Meeting(id: "standup@1", title: "Standup", start: start, end: start, seriesID: "standup")
        #expect(occurrence.isRepeating)
        #expect(occurrence.seriesID == "standup")
    }

    @Test func occurrenceIDIncludesStart() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(Meeting.occurrenceID(eventIdentifier: "evt", start: start) == "evt@1800000000")
        #expect(
            Meeting.occurrenceID(eventIdentifier: "evt", start: start)
                != Meeting.occurrenceID(eventIdentifier: "evt", start: start.addingTimeInterval(86400))
        )
    }
}
