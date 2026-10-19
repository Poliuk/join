import Foundation

/// The Settings toolbar's panes, one subject each, in the toolbar's order: General, Alerts, Calendars,
/// Appearance, with Alerts second since 2026-10-19, at the user's request. The raw values are what the
/// `openSettings` script hook takes (`init(hookArgument:)`), and don't depend on the order.
public enum SettingsPane: String, CaseIterable, Sendable {
    case general
    /// Both kinds of alert, the full-screen alert and the notification, and the snooze durations they share.
    /// Full-Screen Alert (`fullScreenAlert`) until 1.3.0, and third, after Calendars, until 2026-10-19.
    case alerts
    case calendars
    case appearance

    /// The pane's toolbar label and the window's title while it's selected: title-style, as macOS toolbar
    /// labels are.
    public var title: String {
        switch self {
        case .general: return "General"
        case .alerts: return SettingsOptions.alertsPaneTitle
        case .calendars: return "Calendars"
        case .appearance: return "Appearance"
        }
    }

    /// The toolbar item's symbol. Alerts' bell is the panel's Pause alerts symbol.
    public var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .alerts: return "bell"
        case .calendars: return "calendar"
        case .appearance: return "paintpalette"
        }
    }

    /// The pane an `openSettings` hook names: a raw value, or `fullScreenAlert`, the Alerts pane's raw value
    /// until 1.3.0, so scripts written for 1.2.x still open it. Anything else names no pane.
    public init?(hookArgument: String) {
        if let pane = SettingsPane(rawValue: hookArgument) {
            self = pane
        } else if hookArgument == Self.alertsLegacyName {
            self = .alerts
        } else {
            return nil
        }
    }

    /// The Alerts pane's raw value until 1.3.0, when it was Full-Screen Alert.
    static let alertsLegacyName = "fullScreenAlert"
}
