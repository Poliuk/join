import Foundation
import Testing
@testable import JoinCore

/// The notification's planning: `AlertScheduler` with Notify me's lead time and the notification's own states,
/// stopped by a pause or by Never, and never by the full-screen alert.
struct NotificationScheduleTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    /// Notify me 5 minutes before, the default it keeps.
    static let leadTime: TimeInterval = 300
    static let grace = AlertScheduler.lateAlertGrace

    static func meeting(_ id: String, startsIn offset: TimeInterval, duration: TimeInterval = 3600) -> Meeting {
        Meeting(id: id, title: id, start: now.addingTimeInterval(offset), end: now.addingTimeInterval(offset + duration))
    }

    static func plan(
        _ meetings: [Meeting],
        states: [String: AlertState] = [:],
        leadTime: TimeInterval = leadTime,
        isEnabled: Bool = true,
        pause: PauseState = .active,
        at time: Date = now
    ) -> AlertPlan? {
        NotificationSchedule.nextPlan(meetings: meetings, states: states, leadTime: leadTime, isEnabled: isEnabled, pauseState: pause, now: time)
    }

    // MARK: Planning

    /// When a meeting's notification is sent, in seconds from now: Notify me's time before the start, at once
    /// when that's past (after sleep, a late launch, or a Restore from the panel) within the late grace, or when
    /// its snooze ends.
    @Test(arguments: [
        ("pending: Notify me's time before the start", 900, AlertState.pending, 900 - leadTime),
        ("pending, already inside Notify me's time: at once", 120, .pending, 0),
        ("pending, started 4 min ago, within the grace: at once", -240, .pending, 0),
        ("snoozed: when the snooze ends", 900, .snoozed(until: now.addingTimeInterval(60)), 60),
        ("snoozed until the start", 900, .snoozed(until: now.addingTimeInterval(900)), 900),
    ] as [(String, TimeInterval, AlertState, TimeInterval)])
    func sendTime(_ name: String, startsIn offset: TimeInterval, state: AlertState, sentIn expected: TimeInterval) {
        let plan = Self.plan([Self.meeting("a", startsIn: offset)], states: ["a": state])
        #expect(plan?.fireAt == Self.now.addingTimeInterval(expected))
        #expect(plan?.meetings.map(\.id) == ["a"])
    }

    /// Nothing to send: Notify me on Never, a pause (which covers both kinds), a meeting started past the
    /// grace, one that ended, and one whose notification was sent.
    @Test(arguments: [
        ("Notify me is Never", 900, AlertState.pending, false, PauseState.active),
        ("paused for an hour", 900, .pending, true, .until(now.addingTimeInterval(3600))),
        ("paused until resumed", 900, .pending, true, .indefinitely),
        ("started a second past the grace", -(grace + 1), .pending, true, .active),
        ("ended", -7200, .pending, true, .active),
        ("sent", 900, NotificationSchedule.sentState, true, .active),
    ] as [(String, TimeInterval, AlertState, Bool, PauseState)])
    func nothingIsSent(_ name: String, startsIn offset: TimeInterval, state: AlertState, isEnabled: Bool, pause: PauseState) {
        #expect(Self.plan([Self.meeting("a", startsIn: offset)], states: ["a": state], isEnabled: isEnabled, pause: pause) == nil)
    }

    /// When a pause ends, a meeting whose time passed during it is sent at once within the grace, as the
    /// full-screen alert is.
    @Test func aPauseThatEndedLetsADueNotificationThrough() {
        let pause = PauseState.until(Self.now)
        let meeting = Self.meeting("a", startsIn: 120)
        #expect(Self.plan([meeting], pause: pause, at: Self.now.addingTimeInterval(-1)) == nil)
        #expect(Self.plan([meeting], pause: pause)?.fireAt == Self.now)
    }

    /// Meetings at the same time share a plan, and each gets a notification of its own.
    @Test func meetingsAtTheSameTimeAreSentTogether() {
        let plan = Self.plan([Self.meeting("b", startsIn: 900), Self.meeting("a", startsIn: 900), Self.meeting("c", startsIn: 1800)])
        #expect(plan?.meetings.map(\.id) == ["a", "b"])
        let identifiers = plan?.meetings.map { NotificationContent.meeting($0, playsSound: true, now: Self.now).identifier }
        #expect(identifiers == [.meeting("a"), .meeting("b")])
    }

    /// The notification keeps its own time and states: the full-screen alert's time, its Never, and an alert on
    /// screen for the same meeting don't hold it back, so a notification at 5 minutes and the full-screen alert
    /// at the start each come.
    @Test func theFullScreenAlertNeverHoldsANotificationBack() {
        let meeting = Self.meeting("a", startsIn: 900)
        let fullScreenStates: [String: AlertState] = ["a": .showing]
        let fullScreen = AlertScheduler.nextPlan(meetings: [meeting], states: [:], leadTime: 0, isPaused: false, now: Self.now)
        let notification = Self.plan([meeting])
        #expect(fullScreen?.fireAt == meeting.start)
        #expect(notification?.fireAt == meeting.start.addingTimeInterval(-Self.leadTime))
        #expect(AlertScheduler.nextPlan(meetings: [meeting], states: fullScreenStates, leadTime: 0, isPaused: false, now: Self.now) == nil)
    }

    /// A meeting already notified isn't notified again when Notify me's time changes, even to one still ahead.
    @Test(arguments: [0.0, 60, 300, 600, 7200])
    func aSentNotificationIsntSentAgainWhenTheTimeChanges(_ leadTime: TimeInterval) {
        let meeting = Self.meeting("a", startsIn: 900)
        #expect(Self.plan([meeting], states: ["a": NotificationSchedule.sentState], leadTime: leadTime) == nil)
    }

    /// One meeting through its notification's life: sent, snoozed, sent again, then At event start, sent at
    /// the start, and then nothing.
    @Test func aMeetingsNotificationLife() throws {
        let meeting = Self.meeting("a", startsIn: 900)
        var states: [String: AlertState] = [:]
        var time = Self.now

        let first = try #require(Self.plan([meeting], states: states, at: time))
        #expect(first.fireAt == meeting.start.addingTimeInterval(-Self.leadTime))
        time = first.fireAt
        states["a"] = NotificationSchedule.sentState
        #expect(Self.plan([meeting], states: states, at: time) == nil)

        states["a"] = AlertResponse.snooze(60).state(of: .notification, answering: .notification, meeting: meeting, now: time)
        let snoozed = try #require(Self.plan([meeting], states: states, at: time))
        #expect(snoozed.fireAt == time.addingTimeInterval(60))
        time = snoozed.fireAt
        states["a"] = NotificationSchedule.sentState

        states["a"] = AlertResponse.snoozeUntilStart.state(of: .notification, answering: .notification, meeting: meeting, now: time)
        #expect(Self.plan([meeting], states: states, at: time)?.fireAt == meeting.start)
        states["a"] = NotificationSchedule.sentState
        #expect(Self.plan([meeting], states: states, at: meeting.start) == nil)
    }

    // MARK: Asking

    /// Sending waits while Notify me has a time its ask hasn't started for (a preset picked from Never writes
    /// the time first, so a re-plan can come before the ask), and for a minute after asking, so a notification
    /// due at once comes after the user answers macOS's prompt rather than failing before it.
    @Test(arguments: [
        ("Notify me just got a time, not asked yet", true, false, nil, true),
        ("Notify me just got a time, asked a moment ago", true, false, 10, true),
        ("asked 10 s ago", true, true, 10, true),
        ("asked 59 s ago", true, true, 59, true),
        ("asked a minute ago, unanswered", true, true, 60, false),
        ("asked 61 s ago, unanswered", true, true, 61, false),
        ("not asking", true, true, nil, false),
        ("Notify me just went back to Never", false, true, nil, false),
        ("Never, the demo asked 10 s ago", false, false, 10, true),
        ("Never, nothing asked", false, false, nil, false),
    ] as [(String, Bool, Bool, TimeInterval?, Bool)])
    func sendingWaitsForTheAsk(_ name: String, enabled: Bool, handled: Bool, askedAgo: TimeInterval?, holds: Bool) {
        let askedAt = askedAgo.map { Self.now.addingTimeInterval(-$0) }
        #expect(NotificationSchedule.holdsSending(notificationsEnabled: enabled, handledEnabled: handled, askedAt: askedAt, now: Self.now) == holds)
    }

    // MARK: Sound

    /// Play sound decides, except while the meeting's full-screen alert is on screen: the notification comes
    /// silently then, so the two sounds never overlap.
    @Test(arguments: [
        (true, false, true),
        (true, true, false),
        (false, false, false),
        (false, true, false),
    ])
    func sound(preference: Bool, fullScreenAlertShowing: Bool, plays: Bool) {
        #expect(NotificationSchedule.playsSound(preference: preference, fullScreenAlertShowing: fullScreenAlertShowing) == plays)
    }

    // MARK: Withdrawals

    /// A delivered notification is withdrawn once its meeting is no longer alertable (dismissed from the panel,
    /// cancelled, moved to another start, which makes a new occurrence id, or now Show in the list only) or has
    /// ended. The demo's, and notifications Join! didn't make, are left alone.
    @Test func deliveredNotificationsAreWithdrawnWhenTheirMeetingGoes() {
        let ongoing = Self.meeting("ongoing", startsIn: -600)
        let upcoming = Self.meeting("upcoming", startsIn: 600)
        let ended = Self.meeting("ended", startsIn: -7200)
        let delivered = [
            NotificationIdentifier.meeting("ongoing").rawValue,
            NotificationIdentifier.meeting("upcoming").rawValue,
            NotificationIdentifier.meeting("ended").rawValue,
            NotificationIdentifier.meeting("dismissed").rawValue,
            NotificationIdentifier.meeting("event@1800000000").rawValue,
            NotificationIdentifier.demo.rawValue,
            "something else",
        ]
        let withdrawn = NotificationSchedule.withdrawals(delivered: delivered, alertable: [ongoing, upcoming, ended], now: Self.now)
        #expect(withdrawn == ["meeting:ended", "meeting:dismissed", "meeting:event@1800000000"])
    }

    @Test func nothingDeliveredNothingWithdrawn() {
        #expect(NotificationSchedule.withdrawals(delivered: [], alertable: [Self.meeting("a", startsIn: 60)], now: Self.now).isEmpty)
    }

    // MARK: Reopen

    /// A reopen event within a second after a notification response came with the click, so it's ignored and
    /// nothing opens; any other reopen opens Settings as before.
    @Test(arguments: [
        ("no response yet", nil, false),
        ("with the response", 0, true),
        ("half a second after", 0.5, true),
        ("a second after", 1, true),
        ("later", 1.5, false),
        ("before the response, the clock moved", -1, false),
    ] as [(String, TimeInterval?, Bool)])
    func reopenAfterANotificationResponse(_ name: String, after offset: TimeInterval?, ignored: Bool) {
        let response = offset.map { _ in Self.now }
        let time = Self.now.addingTimeInterval(offset ?? 0)
        #expect(NotificationSchedule.ignoresReopen(lastResponse: response, now: time) == ignored)
    }
}
