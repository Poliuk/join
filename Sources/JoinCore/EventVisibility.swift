import Foundation

/// What Join! does with a kind of event Settings › General › Events has a choice for: events with no
/// participants, and out-of-office events. Ordered by how much it shows, so `min` of two choices is
/// the one that shows less, which an event of both kinds gets.
public enum EventVisibility: String, CaseIterable, Comparable, Sendable {
    /// Like any other event: the panel's lists, its card, the menu bar item and both kinds of alert, as each
    /// is set on Alerts.
    case showAndAlert
    /// In the panel's lists only: it never alerts (no full-screen alert, no notification), never drives the
    /// menu bar item and never takes the card.
    case listOnly
    /// Left out everywhere, like the events of an unchecked calendar.
    case exclude

    public var title: String {
        switch self {
        case .showAndAlert: return "Show and alert"
        case .listOnly: return "Show in the list only"
        case .exclude: return "Exclude"
        }
    }

    /// In the panel's lists.
    public var isListed: Bool { self != .exclude }

    /// Free to alert, drive the menu bar item and take the panel's card.
    public var alerts: Bool { self == .showAndAlert }

    public static func < (lhs: EventVisibility, rhs: EventVisibility) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .exclude: return 0
        case .listOnly: return 1
        case .showAndAlert: return 2
        }
    }
}
