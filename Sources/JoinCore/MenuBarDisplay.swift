import Foundation

/// What the menu bar item shows next to its icon. One choice in Settings, stored as the two switches
/// earlier builds kept, `menuBarShowsNextEvent` and `menuBarShowsEventTitles` (`Preferences.menuBarDisplay`).
public enum MenuBarDisplay: String, CaseIterable, Sendable {
    case iconOnly
    case time
    case titleAndTime

    /// From the two stored switches. Titles without the next event (never written) reads as icon only.
    init(showsNextEvent: Bool, showsTitles: Bool) {
        if !showsNextEvent {
            self = .iconOnly
        } else {
            self = showsTitles ? .titleAndTime : .time
        }
    }

    public var title: String {
        switch self {
        case .iconOnly: return "Icon only"
        case .time: return "Time until next event"
        case .titleAndTime: return "Title and time until next event"
        }
    }

    /// The two switches it's stored as.
    var showsNextEvent: Bool { self != .iconOnly }
    var showsTitles: Bool { self == .titleAndTime }
}
