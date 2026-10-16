import Foundation

/// What macOS lets Join!'s notifications do, as System Settings › Notifications › Join! has it. Read again
/// when Join! becomes active and when Settings becomes key, since macOS reports no changes. Keyed to the
/// permission, never to macOS's style names (Banners and Alerts, or Temporary and Persistent), which changed
/// between macOS 15 and 26.
public enum NotificationPermission: Hashable, Sendable {
    /// macOS hasn't asked yet, or the user let its prompt go by unanswered.
    case notDetermined
    /// Declined at the prompt, or Allow notifications turned off for Join! later.
    case denied
    /// Allowed. `showsOnScreen` is false when they go only to Notification Center (an alert style of None, or
    /// the quiet provisional mode Join! never asks for); `playsSound` is macOS's own sound switch for Join!.
    case allowed(showsOnScreen: Bool, playsSound: Bool)

    /// macOS's answer about Join!'s notifications, as its notification settings report it.
    public enum Authorization: Hashable, Sendable {
        case notDetermined
        case denied
        case authorized
        /// The quiet mode Join! never asks for: Notification Center only, no banner and no sound.
        case provisional
    }

    /// Join!'s permission from macOS's notification settings for it: `alertsShown` when its alerts are on
    /// with a style other than None, `soundOn` when its sound switch is on. Provisional delivery reaches only
    /// Notification Center, whatever the style says.
    public init(authorization: Authorization, alertsShown: Bool, soundOn: Bool) {
        switch authorization {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .authorized: self = .allowed(showsOnScreen: alertsShown, playsSound: soundOn)
        case .provisional: self = .allowed(showsOnScreen: false, playsSound: soundOn)
        }
    }

    /// Whether Join! asks macOS now, when Notify me leaves Never or Send Demo Notification is clicked: only
    /// while nothing is decided, since macOS prompts once and answers later requests with the stored choice.
    /// Join! never asks at launch, so an upgrade never prompts.
    public var needsAsking: Bool { self == .notDetermined }

    /// The variable that sets a fixture run's permission, which never comes from macOS: a fixture run shares
    /// the app's bundle id, so it never touches the real notification center.
    public static let fixtureVariable = "JOIN_FIXTURE_NOTIFICATIONS"

    /// A fixture run's permission from `fixtureVariable`: notDetermined, denied, hidden (allowed, never on
    /// screen), soundOff (allowed, macOS's sound off) or authorized. Anything else, or nothing, is
    /// notDetermined, as on a Mac that has never run Join!.
    public static func fixture(_ value: String?) -> NotificationPermission {
        switch value {
        case "denied": return .denied
        case "hidden": return .allowed(showsOnScreen: false, playsSound: true)
        case "soundOff": return .allowed(showsOnScreen: true, playsSound: false)
        case "authorized": return .allowed(showsOnScreen: true, playsSound: true)
        default: return .notDetermined
        }
    }
}

/// The one line at the bottom of the Notification box when something stops a notification from reaching the user, with
/// Open System Settings beside it. Hidden while Notify me is Never, so there's no hint before the user opts in.
/// No line for banners that close on their own: that's macOS's default and the user's choice, which the box's
/// footnote covers.
public enum NotificationStatus: Hashable, Sendable, CaseIterable {
    /// Orange.
    case denied
    /// Orange: allowed, but only into Notification Center.
    case notOnScreen
    /// Secondary: Play sound is on, but macOS's sound for Join! is off.
    case soundOff
    /// Secondary: macOS hasn't asked, or its prompt went unanswered.
    case notAnswered

    /// The line for these settings, one at a time in the order of `allCases`: denied, not on screen, sound
    /// off, not answered. Nil while Notify me is Never (`notificationsEnabled` false) and when nothing is wrong.
    public static func current(
        notificationsEnabled: Bool,
        playsSound: Bool,
        permission: NotificationPermission
    ) -> NotificationStatus? {
        guard notificationsEnabled else { return nil }
        return allCases.first { $0.applies(playsSound: playsSound, permission: permission) }
    }

    private func applies(playsSound: Bool, permission: NotificationPermission) -> Bool {
        switch (self, permission) {
        case (.denied, .denied), (.notAnswered, .notDetermined):
            return true
        case (.notOnScreen, .allowed(let showsOnScreen, _)):
            return !showsOnScreen
        case (.soundOff, .allowed(_, let systemPlaysSound)):
            return playsSound && !systemPlaysSound
        default:
            return false
        }
    }

    public var text: String {
        switch self {
        case .denied: return "Allow notifications for Join! in System Settings › Notifications."
        case .notOnScreen: return "Show Join!'s notifications on screen in System Settings › Notifications."
        case .soundOff: return "Turn on sound for Join! in System Settings › Notifications."
        case .notAnswered: return "Allow notifications from Join! when macOS asks, or in System Settings › Notifications."
        }
    }

    /// Orange, as a `SettingsWarning`, when no notification reaches the screen; secondary text otherwise.
    public var isWarning: Bool {
        switch self {
        case .denied, .notOnScreen: return true
        case .soundOff, .notAnswered: return false
        }
    }

    /// The button beside every line.
    public static let openSettingsTitle = "Open System Settings"

    /// What Open System Settings tries, in order: Notifications › Join! (an undocumented `?id=` form), then
    /// the Notifications pane, the way Open Internet Accounts… falls back.
    public static func settingsURLs(bundleIdentifier: String = "com.poliuk.join") -> [URL] {
        [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleIdentifier)",
            "x-apple.systempreferences:com.apple.preference.notifications",
        ].compactMap(URL.init(string:))
    }
}

/// Send Demo Notification, at the bottom right of the Alerts pane, left of Show Demo: whether it works and its
/// help tag. It sends a real notification for the demo event, so it works while alerts are paused and while
/// Notify me is Never, as Show Demo does; the first click asks macOS when nothing is decided yet.
public struct SendDemoNotificationButton: Equatable, Sendable {
    public static let title = "Send Demo Notification"
    static let help = "Sends a notification with a sample event."
    static let deniedHelp = "Allow notifications for Join! in System Settings first."

    public let isEnabled: Bool
    public let help: String

    /// Off in a fixture run, which never touches the real notification center, and while notifications are
    /// denied, which the help tag explains.
    public init(permission: NotificationPermission, isFixture: Bool) {
        if isFixture {
            isEnabled = false
            help = SettingsOptions.openAtLoginFixtureNote
        } else if permission == .denied {
            isEnabled = false
            help = Self.deniedHelp
        } else {
            isEnabled = true
            help = Self.help
        }
    }
}
