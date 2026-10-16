import Foundation

/// The notification's planning: the second kind of alert (`AlertKind.notification`), planned by
/// `AlertScheduler` unchanged, with Notify me's lead time and the notification's own per-meeting states. Join!
/// posts each notification itself when its plan is due and schedules nothing with macOS ahead, so a pause,
/// Never, the Events choices, panel dismissals, edits and cancellations take effect at once, and a quit or
/// deleted Join! leaves no stale reminders. After sleep or a late launch a notification is sent at once unless
/// its meeting started more than `AlertScheduler.lateAlertGrace` ago, as for the full-screen alert. No timers,
/// no notification center, no clock reads: `now` is always passed in.
public enum NotificationSchedule {
    /// The next notifications due: one for each meeting in the plan, each with its own identifier, so meetings
    /// at the same time each get one. A pause stops them, like the full-screen alert; Never (`isEnabled` false)
    /// stops them alone. The full-screen alert's states and its one-alert-at-a-time rule play no part: a
    /// notification is never held back while a full-screen alert is up.
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
            isPaused: !isEnabled || pauseState.isPaused(at: now),
            now: now
        )
    }

    /// How long sending waits for an answer to macOS's prompt, which may go unanswered for good.
    public static let askingHold: TimeInterval = 60

    /// Whether sending waits, so a notification due at once when Notify me gets a time comes once the user has
    /// answered macOS's prompt rather than failing before it. It waits while Notify me has a time its observer
    /// hasn't handled yet (`handledEnabled` false), whose ask hasn't started: a preset picked from Never writes
    /// the time before Notify me, so a re-plan for the time, the heartbeat's or the fire timer's can come first.
    /// Then for up to `askingHold` after asking (`askedAt`); after that, whatever is due goes out, whatever the
    /// answer.
    public static func holdsSending(notificationsEnabled: Bool, handledEnabled: Bool, askedAt: Date?, now: Date) -> Bool {
        if notificationsEnabled && !handledEnabled { return true }
        guard let askedAt else { return false }
        return now.timeIntervalSince(askedAt) < askingHold
    }

    /// A meeting's state once its notification is sent: done, so it isn't sent again, not even when Notify me's
    /// time changes. A snooze or At event start (`AlertResponse.state`) plans it once more, under the same
    /// identifier, so it replaces itself.
    public static let sentState = AlertState.dismissed

    /// Whether a notification plays its sound: Play sound is on, and its meeting's full-screen alert isn't on
    /// screen, so the two sounds never overlap.
    public static func playsSound(preference: Bool, fullScreenAlertShowing: Bool) -> Bool {
        preference && !fullScreenAlertShowing
    }

    /// The delivered notifications to withdraw, as `identifiers` lists them: those whose meeting is no longer
    /// alertable (dismissed from the panel, cancelled, moved, which gives the occurrence a new id, or now Show
    /// in the list only or excluded) or has ended. A notification that isn't a meeting's, the demo's, is left
    /// for the user to close. `alertable` must come from a loaded calendar: before the first read every
    /// meeting would look gone.
    public static func withdrawals(delivered identifiers: [String], alertable: [Meeting], now: Date) -> [String] {
        let current = Set(alertable.lazy.filter { !$0.hasEnded(at: now) }.map(\.id))
        return identifiers.filter { identifier in
            guard case .meeting(let id) = NotificationIdentifier(rawValue: identifier) else { return false }
            return !current.contains(id)
        }
    }

    /// macOS may send Join! a reopen event along with a click on a notification, and a reopen opens Settings.
    /// Clicking a notification does nothing (the user's choice, 2026-10-16), so reopen events are ignored for
    /// this long after a notification response.
    public static let reopenGrace: TimeInterval = 1

    /// Whether a reopen event at `now` came with the notification response at `lastResponse`, so it's ignored.
    public static func ignoresReopen(lastResponse: Date?, now: Date) -> Bool {
        guard let lastResponse else { return false }
        let elapsed = now.timeIntervalSince(lastResponse)
        return elapsed >= 0 && elapsed <= reopenGrace
    }
}
