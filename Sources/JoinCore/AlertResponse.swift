import Foundation

/// The two kinds of alert, each with its own time or Never on the Alerts pane, its own per-meeting
/// `AlertState`s and its own plan from `AlertScheduler`. "Alerts" covers both: a pause stops both, and so does
/// a panel dismissal.
public enum AlertKind: Hashable, Sendable, CaseIterable {
    /// The window over every screen, at Alert me's time.
    case fullScreen
    /// Join!'s notification card at the top right of the screen, at Notify me's time.
    case notification
}

/// What the user did with an alert of either kind, the full-screen alert's buttons or a notification card's
/// button and menu.
public enum AlertResponse: Hashable, Sendable {
    /// Join: opens the meeting's link.
    case join
    /// A snooze button or menu item: the alert comes back after this long.
    case snooze(TimeInterval)
    /// At event start: the alert comes back when the meeting starts.
    case snoozeUntilStart
    /// Dismiss, or closing automatically: the full-screen alert's Dismiss, Esc and auto-close, and a
    /// notification card's ×, its menu's Dismiss and its Close automatically.
    case close

    /// A snooze until the start that's less than this far ahead finishes the alert instead, as the full-screen
    /// alert's At event start always has: the meeting is starting.
    static let startingTolerance: TimeInterval = 1

    /// The state of `kind` for `meeting` once the user has answered an alert of kind `source`, or nil to leave
    /// it as it is. Join, from either kind or the menu bar panel, finishes both: the meeting is joined, so
    /// neither comes back.
    /// Snooze, At event start and close act on their own kind only, so a gentle-then-loud setup (a notification
    /// 5 minutes before, the full-screen alert at the start) still brings the full-screen alert when a
    /// notification is snoozed or closed, and dismissing the full-screen alert leaves the card (the user's
    /// choice, 2026-10-19). At event start finishes the alert once the meeting has started.
    public func state(of kind: AlertKind, answering source: AlertKind, meeting: Meeting, now: Date) -> AlertState? {
        switch self {
        case .join:
            return .dismissed
        case .snooze, .snoozeUntilStart, .close:
            guard kind == source else { return nil }
            return ownState(meeting: meeting, now: now)
        }
    }

    private func ownState(meeting: Meeting, now: Date) -> AlertState {
        switch self {
        case .join, .close:
            return .dismissed
        case .snooze(let duration):
            return .snoozed(until: now.addingTimeInterval(duration))
        case .snoozeUntilStart:
            return meeting.start > now.addingTimeInterval(Self.startingTolerance) ? .snoozed(until: meeting.start) : .dismissed
        }
    }
}
