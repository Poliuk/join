import Foundation
import Testing
@testable import JoinCore

struct AlertSchedulerTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let leadTime: TimeInterval = 180
    static let grace = AlertScheduler.lateAlertGrace

    static func meeting(_ id: String, startsIn offset: TimeInterval, duration: TimeInterval = 3600) -> Meeting {
        Meeting(id: id, title: id, start: now.addingTimeInterval(offset), end: now.addingTimeInterval(offset + duration))
    }

    static func plan(_ meetings: [Meeting], states: [String: AlertState] = [:], paused: Bool = false) -> AlertPlan? {
        AlertScheduler.nextPlan(meetings: meetings, states: states, leadTime: leadTime, isPaused: paused, now: now)
    }

    /// When one meeting's alert fires, in seconds from now: the lead time before the start, at once when that's
    /// past, or when its snooze ends. The late grace only spares the user pending meetings they never saw: a snooze
    /// they chose fires however long after the start it lands.
    @Test(arguments: [
        ("pending: the lead time before the start", 600, AlertState.pending, 600 - leadTime),
        ("pending, already inside the lead time: at once", 60, .pending, 0),
        ("pending, started 2 min ago, within the grace: at once", -120, .pending, 0),
        ("snoozed: when the snooze ends", 600, .snoozed(until: now.addingTimeInterval(45)), 45),
        ("snoozed, the snooze passed while the Mac slept: at once", 600, .snoozed(until: now.addingTimeInterval(-30)), 0),
        ("snoozed, landing 10 min after the start", -600, .snoozed(until: now.addingTimeInterval(60)), 60),
    ] as [(String, TimeInterval, AlertState, TimeInterval)])
    func fireTimeForOneMeeting(_ name: String, startsIn offset: TimeInterval, state: AlertState, firesIn expected: TimeInterval) {
        let result = Self.plan([Self.meeting("a", startsIn: offset)], states: ["a": state])
        #expect(result?.fireAt == Self.now.addingTimeInterval(expected))
        #expect(result?.meetings.map(\.id) == ["a"])
    }

    /// Nothing to plan: a meeting the app was launched too late for (the grace ends exactly `lateAlertGrace` after
    /// the start), an ended one even while snoozed, one already showing or dismissed (from the panel, since 1.2.0),
    /// and anything while paused, which is also how Alert me = Never reaches the scheduler.
    @Test(arguments: [
        ("started a second past the grace", -(grace + 1), 3600, AlertState.pending, false),
        ("started exactly the grace ago", -grace, 3600, .pending, false),
        ("ended", -7200, 3600, .pending, false),
        ("ended while snoozed", -7200, 3600, .snoozed(until: now.addingTimeInterval(60)), false),
        ("showing", 600, 3600, .showing, false),
        ("dismissed", 600, 3600, .dismissed, false),
        ("paused", 600, 3600, .pending, true),
    ] as [(String, TimeInterval, TimeInterval, AlertState, Bool)])
    func noAlertIsPlanned(_ name: String, startsIn offset: TimeInterval, duration: TimeInterval, state: AlertState, paused: Bool) {
        #expect(Self.plan([Self.meeting("a", startsIn: offset, duration: duration)], states: ["a": state], paused: paused) == nil)
    }

    /// The earliest fire time wins, wherever its meeting is in the list. Meetings firing within `groupingWindow`
    /// (1 s) of it share its alert, listed by start time, then title.
    @Test(arguments: [
        ("the same fire time, half a second apart", [("b", 600), ("a", 600.5), ("c", 900)], ["b", "a"]),
        ("exactly a second apart", [("b", 600), ("a", 601)], ["b", "a"]),
        ("more than a second apart", [("b", 600), ("a", 601.5)], ["b"]),
        ("the same start, by title", [("b", 600), ("a", 600)], ["a", "b"]),
        ("the earliest last in the list", [("later", 900), ("sooner", 600)], ["sooner"]),
    ] as [(String, [(id: String, startsIn: TimeInterval)], [String])])
    func alertGroupsTheEarliestMeetings(_ name: String, meetings: [(id: String, startsIn: TimeInterval)], expected: [String]) throws {
        let earliest = try #require(meetings.map(\.startsIn).min())
        let result = Self.plan(meetings.map { Self.meeting($0.id, startsIn: $0.startsIn) })
        #expect(result?.fireAt == Self.now.addingTimeInterval(earliest - Self.leadTime))
        #expect(result?.meetings.map(\.id) == expected)
    }
}
