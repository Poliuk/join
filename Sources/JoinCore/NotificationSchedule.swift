import Foundation

/// The notification's planning: the second kind of alert (`AlertKind.notification`), planned by
/// `AlertScheduler` unchanged, with Notify me's lead time and the notification's own per-meeting states. Join!
/// shows each notification card itself when its plan is due and schedules nothing ahead, so a pause, Never,
/// the Events choices, panel dismissals, edits and cancellations take effect at once. After sleep or a late
/// launch a card comes at once unless its meeting started more than `AlertScheduler.lateAlertGrace` ago, as for
/// the full-screen alert. No timers, no windows, no clock reads: `now` is always passed in.
public enum NotificationSchedule {
    /// The next cards due: one for each meeting in the plan, so meetings at the same time each get one. A pause
    /// stops them, like the full-screen alert; Never (`isEnabled` false) stops them alone. The full-screen
    /// alert's states and its one-alert-at-a-time rule play no part: a card is never held back while a
    /// full-screen alert is up.
    public static func nextPlan(
        meetings: [Meeting],
        states: [Meeting.ID: AlertState],
        leadTime: TimeInterval,
        isEnabled: Bool,
        pauseState: PauseState,
        now: Date
    ) -> AlertPlan? {
        AlertScheduler.nextPlan(
            meetings: meetings,
            states: states,
            leadTime: leadTime,
            isPaused: isStopped(isEnabled: isEnabled, pauseState: pauseState, now: now),
            now: now
        )
    }

    /// Whether cards are stopped: alerts are paused, or Notify me is Never. Then nothing is planned and the
    /// meetings' cards on screen close (`hiddenState`); Test Notification's card stays, as it works either way.
    public static func isStopped(isEnabled: Bool, pauseState: PauseState, now: Date) -> Bool {
        !isEnabled || pauseState.isPaused(at: now)
    }

    /// A meeting's state while its card is on screen: planned no more, not even when Notify me's time changes,
    /// and shown again after a relaunch while `reshowsAfterRelaunch` says so. A snooze or At event start
    /// (`AlertResponse.state`) plans it once more.
    public static let shownState = AlertState.showing

    /// A meeting's state once its card closes because alerts were paused or Notify me went to Never, which
    /// the user didn't answer: due again, so when the pause ends or Notify me gets a time, the card comes back
    /// at once, unless its meeting started more than `AlertScheduler.lateAlertGrace` ago.
    public static let hiddenState = AlertState.pending

    /// Whether a card plays its sound as it appears or comes back from a snooze: Play sound is on, and its
    /// meeting's full-screen alert isn't on screen, so the two sounds never overlap.
    public static func playsSound(preference: Bool, fullScreenAlertShowing: Bool) -> Bool {
        preference && !fullScreenAlertShowing
    }

    /// When a card that appeared at `appearedAt` closes itself, which counts as Dismiss (`AlertResponse.close`):
    /// Close automatically's time after each appearance, a snooze's return included; nil with Never.
    public static func autoCloseTime(appearedAt: Date, isEnabled: Bool, after: TimeInterval) -> Date? {
        isEnabled ? appearedAt.addingTimeInterval(after) : nil
    }

    /// Whether a card on screen when Join! quit, which appeared at `appearedAt`, comes back, silently, at the
    /// next launch: its meeting hasn't ended and its close-automatically time hasn't come. A meeting gone from
    /// the calendar or no longer alertable is the caller's to leave out, as for a withdrawal.
    public static func reshowsAfterRelaunch(
        meeting: Meeting,
        appearedAt: Date,
        autoCloseEnabled: Bool,
        autoCloseAfter: TimeInterval,
        now: Date
    ) -> Bool {
        guard !meeting.hasEnded(at: now) else { return false }
        guard let closesAt = autoCloseTime(appearedAt: appearedAt, isEnabled: autoCloseEnabled, after: autoCloseAfter) else { return true }
        return now < closesAt
    }

    /// The cards to withdraw, of the meetings whose cards are on screen or waiting (`shown`): those whose
    /// meeting is no longer alertable (dismissed from the panel, cancelled, moved, which gives the occurrence a
    /// new id, or now Show in the list only or excluded) or has ended. Test Notification's card is left for
    /// the user to close. `alertable` must come from a loaded calendar: before the first read every meeting
    /// would look gone.
    public static func withdrawals(shown: [Meeting.ID], alertable: [Meeting], now: Date) -> [Meeting.ID] {
        let current = Set(alertable.lazy.filter { !$0.hasEnded(at: now) }.map(\.id))
        return shown.filter { $0 != DemoEvent.id && !current.contains($0) }
    }
}
