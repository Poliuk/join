import XCTest
@testable import JoinCore

final class AlertSchedulerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let leadTime: TimeInterval = 180

    func meeting(_ id: String, startsIn offset: TimeInterval, duration: TimeInterval = 3600) -> Meeting {
        Meeting(id: id, title: id, start: now.addingTimeInterval(offset), end: now.addingTimeInterval(offset + duration))
    }

    func plan(_ meetings: [Meeting], states: [String: AlertState] = [:], paused: Bool = false) -> AlertPlan? {
        AlertScheduler.nextPlan(meetings: meetings, states: states, leadTime: leadTime, isPaused: paused, now: now)
    }

    func testPendingMeetingFiresLeadTimeBeforeStart() {
        let result = plan([meeting("a", startsIn: 600)])
        XCTAssertEqual(result?.fireAt, now.addingTimeInterval(600 - leadTime))
        XCTAssertEqual(result?.meetings.map(\.id), ["a"])
    }

    func testOverdueMeetingFiresImmediately() {
        let result = plan([meeting("late", startsIn: 60)])
        XCTAssertEqual(result?.fireAt, now)
    }

    func testMeetingThatStartedWithinGraceStillFires() {
        let result = plan([meeting("started", startsIn: -120)])
        XCTAssertEqual(result?.fireAt, now)
    }

    func testMeetingThatStartedLongAgoIsSkipped() {
        XCTAssertNil(plan([meeting("old", startsIn: -(AlertScheduler.lateAlertGrace + 1))]))
    }

    func testEndedMeetingIsSkipped() {
        XCTAssertNil(plan([meeting("done", startsIn: -7200, duration: 3600)]))
    }

    func testSnoozedMeetingFiresAtSnoozeTime() {
        let until = now.addingTimeInterval(45)
        let result = plan([meeting("a", startsIn: 600)], states: ["a": .snoozed(until: until)])
        XCTAssertEqual(result?.fireAt, until)
    }

    func testExpiredSnoozeFiresNow() {
        let result = plan([meeting("a", startsIn: 600)], states: ["a": .snoozed(until: now.addingTimeInterval(-30))])
        XCTAssertEqual(result?.fireAt, now)
    }

    func testShowingAndDismissedProduceNothing() {
        XCTAssertNil(plan([meeting("a", startsIn: 600)], states: ["a": .showing]))
        XCTAssertNil(plan([meeting("a", startsIn: 600)], states: ["a": .dismissed]))
    }

    func testPausedReturnsNil() {
        XCTAssertNil(plan([meeting("a", startsIn: 600)], paused: true))
    }

    func testMeetingsWithTheSameFireTimeShareOneAlert() {
        let result = plan([meeting("b", startsIn: 600), meeting("a", startsIn: 600.5), meeting("c", startsIn: 900)])
        XCTAssertEqual(result?.meetings.map(\.id), ["b", "a"])
    }

    func testEarliestMeetingWins() {
        let result = plan([meeting("later", startsIn: 900), meeting("sooner", startsIn: 600)])
        XCTAssertEqual(result?.meetings.map(\.id), ["sooner"])
    }

    func testStateRoundTripsThroughJSON() throws {
        let states: [String: AlertState] = ["a": .snoozed(until: now), "b": .dismissed, "c": .pending]
        let data = try JSONEncoder().encode(states)
        XCTAssertEqual(try JSONDecoder().decode([String: AlertState].self, from: data), states)
    }
}
