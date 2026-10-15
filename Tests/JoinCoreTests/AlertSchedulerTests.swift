import Foundation
import Testing
@testable import JoinCore

struct AlertSchedulerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let leadTime: TimeInterval = 180

    func meeting(_ id: String, startsIn offset: TimeInterval, duration: TimeInterval = 3600) -> Meeting {
        Meeting(id: id, title: id, start: now.addingTimeInterval(offset), end: now.addingTimeInterval(offset + duration))
    }

    func plan(_ meetings: [Meeting], states: [String: AlertState] = [:], paused: Bool = false) -> AlertPlan? {
        AlertScheduler.nextPlan(meetings: meetings, states: states, leadTime: leadTime, isPaused: paused, now: now)
    }

    @Test func pendingMeetingFiresLeadTimeBeforeStart() {
        let result = plan([meeting("a", startsIn: 600)])
        #expect(result?.fireAt == now.addingTimeInterval(600 - leadTime))
        #expect(result?.meetings.map(\.id) == ["a"])
    }

    @Test func overdueMeetingFiresImmediately() {
        let result = plan([meeting("late", startsIn: 60)])
        #expect(result?.fireAt == now)
    }

    @Test func meetingThatStartedWithinGraceStillFires() {
        let result = plan([meeting("started", startsIn: -120)])
        #expect(result?.fireAt == now)
    }

    @Test func meetingThatStartedLongAgoIsSkipped() {
        #expect(plan([meeting("old", startsIn: -(AlertScheduler.lateAlertGrace + 1))]) == nil)
    }

    @Test func endedMeetingIsSkipped() {
        #expect(plan([meeting("done", startsIn: -7200, duration: 3600)]) == nil)
    }

    @Test func snoozedMeetingFiresAtSnoozeTime() {
        let until = now.addingTimeInterval(45)
        let result = plan([meeting("a", startsIn: 600)], states: ["a": .snoozed(until: until)])
        #expect(result?.fireAt == until)
    }

    @Test func expiredSnoozeFiresNow() {
        let result = plan([meeting("a", startsIn: 600)], states: ["a": .snoozed(until: now.addingTimeInterval(-30))])
        #expect(result?.fireAt == now)
    }

    @Test func showingAndDismissedProduceNothing() {
        #expect(plan([meeting("a", startsIn: 600)], states: ["a": .showing]) == nil)
        #expect(plan([meeting("a", startsIn: 600)], states: ["a": .dismissed]) == nil)
    }

    @Test func pausedReturnsNil() {
        #expect(plan([meeting("a", startsIn: 600)], paused: true) == nil)
    }

    @Test func meetingsWithTheSameFireTimeShareOneAlert() {
        let result = plan([meeting("b", startsIn: 600), meeting("a", startsIn: 600.5), meeting("c", startsIn: 900)])
        #expect(result?.meetings.map(\.id) == ["b", "a"])
    }

    @Test func earliestMeetingWins() {
        let result = plan([meeting("later", startsIn: 900), meeting("sooner", startsIn: 600)])
        #expect(result?.meetings.map(\.id) == ["sooner"])
    }
}
