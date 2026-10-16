import Foundation
import Testing
@testable import JoinCore

/// What answering one kind of alert does to both: Join finishes both kinds for the meeting; Snooze, At event
/// start and close act on their own kind only.
struct AlertResponseTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let upcoming = Meeting(id: "a", title: "Design review", start: now.addingTimeInterval(240), end: now.addingTimeInterval(2040))
    static let started = Meeting(id: "b", title: "Standup", start: now.addingTimeInterval(-60), end: now.addingTimeInterval(840))

    struct Case: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let response: AlertResponse
        let source: AlertKind
        let meeting: Meeting
        /// The full-screen alert's state afterwards, then the notification's; nil leaves it.
        let fullScreen: AlertState?
        let notification: AlertState?
    }

    static let cases: [Case] = [
        Case(testDescription: "Join on the full-screen alert", response: .join, source: .fullScreen, meeting: upcoming,
             fullScreen: .dismissed, notification: .dismissed),
        Case(testDescription: "Join on a notification", response: .join, source: .notification, meeting: upcoming,
             fullScreen: .dismissed, notification: .dismissed),
        Case(testDescription: "a snooze on the full-screen alert", response: .snooze(60), source: .fullScreen, meeting: upcoming,
             fullScreen: .snoozed(until: now.addingTimeInterval(60)), notification: nil),
        Case(testDescription: "a snooze on a notification", response: .snooze(300), source: .notification, meeting: upcoming,
             fullScreen: nil, notification: .snoozed(until: now.addingTimeInterval(300))),
        Case(testDescription: "At event start on the full-screen alert", response: .snoozeUntilStart, source: .fullScreen, meeting: upcoming,
             fullScreen: .snoozed(until: upcoming.start), notification: nil),
        Case(testDescription: "At event start on a notification", response: .snoozeUntilStart, source: .notification, meeting: upcoming,
             fullScreen: nil, notification: .snoozed(until: upcoming.start)),
        Case(testDescription: "At event start once the meeting has started", response: .snoozeUntilStart, source: .notification,
             meeting: started, fullScreen: nil, notification: .dismissed),
        Case(testDescription: "the full-screen alert's Dismiss", response: .close, source: .fullScreen, meeting: upcoming,
             fullScreen: .dismissed, notification: nil),
        Case(testDescription: "a notification closed", response: .close, source: .notification, meeting: upcoming,
             fullScreen: nil, notification: .dismissed),
    ]

    @Test(arguments: cases)
    func stateOfEachKind(_ test: Case) {
        #expect(test.response.state(of: .fullScreen, answering: test.source, meeting: test.meeting, now: Self.now) == test.fullScreen)
        #expect(test.response.state(of: .notification, answering: test.source, meeting: test.meeting, now: Self.now) == test.notification)
    }

    /// At event start less than a second before the start finishes the alert, as the full-screen alert's has.
    @Test(arguments: [(1.5, true), (1, false), (0.5, false)] as [(TimeInterval, Bool)])
    func atEventStartRightBeforeTheStart(startsIn offset: TimeInterval, snoozes: Bool) {
        let meeting = Meeting(id: "c", title: "Sync", start: Self.now.addingTimeInterval(offset), end: Self.now.addingTimeInterval(1800))
        let state = AlertResponse.snoozeUntilStart.state(of: .notification, answering: .notification, meeting: meeting, now: Self.now)
        #expect(state == (snoozes ? .snoozed(until: meeting.start) : .dismissed))
    }
}
