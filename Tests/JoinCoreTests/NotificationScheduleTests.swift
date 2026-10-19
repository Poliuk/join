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

    /// When a meeting's card is shown, in seconds from now: Notify me's time before the start, at once
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

    /// Nothing to show: Notify me on Never, a pause (which covers both kinds), a meeting started past the
    /// grace, one that ended, one whose card is on screen and one whose card was closed.
    @Test(arguments: [
        ("Notify me is Never", 900, AlertState.pending, false, PauseState.active),
        ("paused for an hour", 900, .pending, true, .until(now.addingTimeInterval(3600))),
        ("paused until resumed", 900, .pending, true, .indefinitely),
        ("started a second past the grace", -(grace + 1), .pending, true, .active),
        ("ended", -7200, .pending, true, .active),
        ("on screen", 900, NotificationSchedule.shownState, true, .active),
        ("dismissed", 900, .dismissed, true, .active),
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

    /// Meetings at the same time share a plan, and each gets a card of its own.
    @Test func meetingsAtTheSameTimeAreShownTogether() {
        let plan = Self.plan([Self.meeting("b", startsIn: 900), Self.meeting("a", startsIn: 900), Self.meeting("c", startsIn: 1800)])
        #expect(plan?.meetings.map(\.id) == ["a", "b"])
        #expect(plan?.meetings.map { NotificationCard.meeting($0).id } == ["a", "b"])
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

    /// A meeting whose card is on screen, or was closed, isn't planned again when Notify me's time changes, even
    /// to one still ahead.
    @Test(arguments: [0.0, 60, 300, 600, 7200])
    func aShownCardIsntShownAgainWhenTheTimeChanges(_ leadTime: TimeInterval) {
        let meeting = Self.meeting("a", startsIn: 900)
        #expect(Self.plan([meeting], states: ["a": NotificationSchedule.shownState], leadTime: leadTime) == nil)
        #expect(Self.plan([meeting], states: ["a": .dismissed], leadTime: leadTime) == nil)
    }

    /// One meeting through its card's life: shown, snoozed, shown again, then At event start, shown at the
    /// start, closed (Dismiss, or closing automatically), and then nothing.
    @Test func aMeetingsCardLife() throws {
        let meeting = Self.meeting("a", startsIn: 900)
        var states: [String: AlertState] = [:]
        var time = Self.now

        let first = try #require(Self.plan([meeting], states: states, at: time))
        #expect(first.fireAt == meeting.start.addingTimeInterval(-Self.leadTime))
        time = first.fireAt
        states["a"] = NotificationSchedule.shownState
        #expect(Self.plan([meeting], states: states, at: time) == nil)

        states["a"] = AlertResponse.snooze(60).state(of: .notification, answering: .notification, meeting: meeting, now: time)
        let snoozed = try #require(Self.plan([meeting], states: states, at: time))
        #expect(snoozed.fireAt == time.addingTimeInterval(60))
        time = snoozed.fireAt
        states["a"] = NotificationSchedule.shownState

        states["a"] = AlertResponse.snoozeUntilStart.state(of: .notification, answering: .notification, meeting: meeting, now: time)
        #expect(Self.plan([meeting], states: states, at: time)?.fireAt == meeting.start)
        states["a"] = NotificationSchedule.shownState
        #expect(Self.plan([meeting], states: states, at: meeting.start) == nil)

        states["a"] = AlertResponse.close.state(of: .notification, answering: .notification, meeting: meeting, now: meeting.start)
        #expect(states["a"] == .dismissed)
        #expect(Self.plan([meeting], states: states, at: meeting.start) == nil)
    }

    // MARK: Pause and Never

    /// Cards stop, and those on screen close, while alerts are paused or Notify me is Never.
    @Test(arguments: [
        ("Notify me has a time", true, PauseState.active, false),
        ("Notify me is Never", false, .active, true),
        ("paused for an hour", true, .until(now.addingTimeInterval(3600)), true),
        ("paused until resumed", true, .indefinitely, true),
        ("a pause that ended", true, .until(now), false),
    ] as [(String, Bool, PauseState, Bool)])
    func cardsStop(_ name: String, isEnabled: Bool, pause: PauseState, stopped: Bool) {
        #expect(NotificationSchedule.isStopped(isEnabled: isEnabled, pauseState: pause, now: Self.now) == stopped)
    }

    /// A card closed by a pause or by Never wasn't answered: once the pause ends, or Notify me gets a time, it
    /// comes back at once, unless its meeting started more than the late grace ago.
    @Test(arguments: [
        ("before the start", 120, true),
        ("started 4 minutes ago", -240, true),
        ("started past the grace", -(grace + 1), false),
    ] as [(String, TimeInterval, Bool)])
    func aCardClosedByAPauseComesBackWhenItEnds(_ name: String, startsIn offset: TimeInterval, comesBack: Bool) {
        let meeting = Self.meeting("a", startsIn: offset)
        let states = ["a": NotificationSchedule.hiddenState]
        #expect(Self.plan([meeting], states: states, pause: .indefinitely) == nil)
        #expect(Self.plan([meeting], states: states, isEnabled: false) == nil)
        #expect((Self.plan([meeting], states: states)?.fireAt == Self.now) == comesBack)
    }

    // MARK: Sound

    /// Play sound decides, except while the meeting's full-screen alert is on screen: the card comes silently
    /// then, so the two sounds never overlap.
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

    /// A card on screen or waiting is withdrawn once its meeting is no longer alertable (dismissed from the
    /// panel, cancelled, moved to another start, which makes a new occurrence id, or now Show in the list only)
    /// or has ended. Test Notification's card is left alone.
    @Test func cardsAreWithdrawnWhenTheirMeetingGoes() {
        let ongoing = Self.meeting("ongoing", startsIn: -600)
        let upcoming = Self.meeting("upcoming", startsIn: 600)
        let ended = Self.meeting("ended", startsIn: -7200)
        let shown = ["ongoing", "upcoming", "ended", "dismissed", "event@1800000000", DemoEvent.id]
        let withdrawn = NotificationSchedule.withdrawals(shown: shown, alertable: [ongoing, upcoming, ended], now: Self.now)
        #expect(withdrawn == ["ended", "dismissed", "event@1800000000"])
    }

    @Test func nothingShownNothingWithdrawn() {
        #expect(NotificationSchedule.withdrawals(shown: [], alertable: [Self.meeting("a", startsIn: 60)], now: Self.now).isEmpty)
    }

    // MARK: Closing automatically and relaunching

    /// Close automatically's time after each appearance, a snooze's return included; nothing with Never.
    @Test(arguments: [
        (true, 600.0, 600.0),
        (true, 60, 60),
        (false, 600, nil),
    ] as [(Bool, TimeInterval, TimeInterval?)])
    func closesAutomatically(isEnabled: Bool, after: TimeInterval, closesIn expected: TimeInterval?) {
        let appeared = Self.now.addingTimeInterval(-30)
        #expect(
            NotificationSchedule.autoCloseTime(appearedAt: appeared, isEnabled: isEnabled, after: after)
                == expected.map { appeared.addingTimeInterval($0) }
        )
    }

    /// A card on screen when Join! quit comes back at the next launch while its meeting hasn't ended and its
    /// close-automatically time hasn't come; with Never, until its meeting ends.
    @Test(arguments: [
        ("appeared a minute ago", -60, true, true),
        ("a second before it would close", -599, true, true),
        ("its time to close came", -600, true, false),
        ("it would have closed", -900, true, false),
        ("Never, appeared long ago", -3000, false, true),
    ] as [(String, TimeInterval, Bool, Bool)])
    func aCardOnScreenAtQuitComesBack(_ name: String, appeared offset: TimeInterval, autoCloseEnabled: Bool, reshows: Bool) {
        let meeting = Self.meeting("a", startsIn: 120)
        let comesBack = NotificationSchedule.reshowsAfterRelaunch(
            meeting: meeting, appearedAt: Self.now.addingTimeInterval(offset),
            autoCloseEnabled: autoCloseEnabled, autoCloseAfter: 600, now: Self.now
        )
        #expect(comesBack == reshows)
    }

    @Test(arguments: [true, false])
    func aCardWhoseMeetingEndedDoesntComeBack(autoCloseEnabled: Bool) {
        let ended = Self.meeting("a", startsIn: -3600, duration: 3500)
        let comesBack = NotificationSchedule.reshowsAfterRelaunch(
            meeting: ended, appearedAt: Self.now.addingTimeInterval(-60),
            autoCloseEnabled: autoCloseEnabled, autoCloseAfter: 600, now: Self.now
        )
        #expect(!comesBack)
    }
}
