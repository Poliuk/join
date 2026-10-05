import Foundation

/// What the menu bar item shows next to its icon. One choice in Settings, stored as the two
/// existing preferences (`menuBarShowsNextEvent`, `menuBarShowsEventTitles`).
public enum MenuBarDisplay: String, CaseIterable, Sendable {
    case iconOnly
    case time
    case titleAndTime

    public init(showsNextEvent: Bool, showsTitles: Bool) {
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

    public var showsNextEvent: Bool { self != .iconOnly }
    public var showsTitles: Bool { self == .titleAndTime }
}

extension Preferences {
    public var menuBarDisplay: MenuBarDisplay {
        get { MenuBarDisplay(showsNextEvent: menuBarShowsNextEvent, showsTitles: menuBarShowsEventTitles) }
        set {
            menuBarShowsNextEvent = newValue.showsNextEvent
            // Keep the title choice when switching to icon only, so switching back restores it.
            if newValue != .iconOnly { menuBarShowsEventTitles = newValue.showsTitles }
        }
    }
}
