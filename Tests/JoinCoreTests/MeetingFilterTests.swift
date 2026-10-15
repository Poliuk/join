import Foundation
import Testing
@testable import JoinCore

struct MeetingFilterTests {
    /// What reaches the list at all: not all-day, not canceled, not declined. Maybe and unanswered count.
    @Test(arguments: [
        ("an accepted event", false, false, .accepted, true),
        ("a Maybe", false, false, .tentative, true),
        ("an unanswered invitation", false, false, .unknown, true),
        ("a declined event", false, false, .declined, false),
        ("an all-day event", true, false, .accepted, false),
        ("a canceled event", false, true, .accepted, false),
    ] as [(String, Bool, Bool, ParticipationStatus, Bool)])
    func shouldInclude(_ name: String, isAllDay: Bool, isCanceled: Bool, status: ParticipationStatus, included: Bool) {
        #expect(MeetingFilter.shouldInclude(isAllDay: isAllDay, isCanceled: isCanceled, myStatus: status) == included)
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

    /// One event of each kind: an out-of-office one, an ordinary one, one out of office with no participants,
    /// and one with no participants. Not in alphabetical order, so the tables also show the filters keep the
    /// order they're given.
    private var kinds: [Meeting] {
        [
            meeting("ooo", participants: true, outOfOffice: true),
            meeting("call", participants: true),
            meeting("ooo-solo", participants: false, outOfOffice: true),
            meeting("focus", participants: false),
        ]
    }

    /// Every pair of Events choices (no participants, out of office): the events listed, and those that can
    /// alert. An ordinary event always shows and alerts, and one of both kinds gets the choice that shows less.
    @Test(arguments: EventVisibility.allCases, EventVisibility.allCases)
    func everyCombinationOfChoices(withoutParticipants: EventVisibility, outOfOffice: EventVisibility) {
        let all = ["ooo", "call", "ooo-solo", "focus"]
        let (visible, alertable): ([String], [String]) = switch (withoutParticipants, outOfOffice) {
        case (.showAndAlert, .showAndAlert): (all, all)
        case (.showAndAlert, .listOnly): (all, ["call", "focus"])
        case (.showAndAlert, .exclude): (["call", "focus"], ["call", "focus"])
        case (.listOnly, .showAndAlert): (all, ["ooo", "call"])
        case (.listOnly, .listOnly): (all, ["call"])
        case (.listOnly, .exclude): (["call", "focus"], ["call"])
        case (.exclude, .showAndAlert): (["ooo", "call"], ["ooo", "call"])
        case (.exclude, .listOnly): (["ooo", "call"], ["call"])
        case (.exclude, .exclude): (["call"], ["call"])
        }
        #expect(MeetingFilter.visible(kinds, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice).map(\.id) == visible)
        #expect(MeetingFilter.alertable(kinds, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice).map(\.id) == alertable)
    }

    /// Maybe and unanswered events follow the choice like accepted ones: unlike the menu bar, which follows
    /// the meetings you attend, the choice doesn't look at your answer.
    @Test(arguments: [ParticipationStatus.accepted, .tentative, .unknown])
    func yourAnswerDoesNotChangeTheChoice(_ status: ParticipationStatus) {
        let meetings = [meeting("call", participants: true, status: status), meeting("hold", participants: false, status: status)]
        #expect(MeetingFilter.visible(meetings, eventsWithoutParticipants: .exclude, outOfOfficeEvents: .listOnly).map(\.id) == ["call"])
        #expect(MeetingFilter.alertable(meetings, eventsWithoutParticipants: .listOnly, outOfOfficeEvents: .listOnly).map(\.id) == ["call"])
        #expect(MeetingFilter.alertable(meetings, eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .listOnly).map(\.id)
                == ["call", "hold"])
    }

    // MARK: Dismissed events

    /// Every kind but the one of both kinds dismissed. Only an event that could alert is dismissed: one whose
    /// choice became Show in the list only (or Exclude) after it was dismissed is shown according to the new
    /// choice. The Show and alert events are split between alertable and dismissed.
    @Test(arguments: EventVisibility.allCases, EventVisibility.allCases)
    func dismissedIDsAreTheShowAndAlertOnesOnly(withoutParticipants: EventVisibility, outOfOffice: EventVisibility) {
        let dismissed = DismissedEvents().dismissing(kinds[0]).dismissing(kinds[1]).dismissing(kinds[3])
        let expected: Set<String> = switch (withoutParticipants, outOfOffice) {
        case (.showAndAlert, .showAndAlert): ["ooo", "call", "focus"]
        case (.showAndAlert, .listOnly), (.showAndAlert, .exclude): ["call", "focus"]
        case (.listOnly, .showAndAlert), (.exclude, .showAndAlert): ["ooo", "call"]
        case (.listOnly, .listOnly), (.listOnly, .exclude), (.exclude, .listOnly), (.exclude, .exclude): ["call"]
        }
        func ids(_ meetings: [Meeting], _ dismissed: DismissedEvents) -> Set<String> {
            MeetingFilter.dismissedIDs(meetings, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice, dismissed: dismissed)
        }
        #expect(ids(kinds, dismissed) == expected)

        let all = MeetingFilter.alertable(kinds, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice)
        let alertable = MeetingFilter.alertable(kinds, eventsWithoutParticipants: withoutParticipants, outOfOfficeEvents: outOfOffice, dismissed: dismissed)
        #expect(Set(alertable.map(\.id)).union(expected) == Set(all.map(\.id)))
        #expect(Set(alertable.map(\.id)).isDisjoint(with: expected))

        #expect(ids(kinds, DismissedEvents()).isEmpty)
        #expect(ids([], dismissed).isEmpty, "an entry with no meeting (ended, or its calendar unchecked) shows nowhere")
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
}
