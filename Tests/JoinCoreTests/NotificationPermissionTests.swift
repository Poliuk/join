import Foundation
import Testing
@testable import JoinCore

/// What macOS allows, the status line under the Notification box, its Open System Settings, and Send Demo
/// Notification.
struct NotificationPermissionTests {
    static let allowed = NotificationPermission.allowed(showsOnScreen: true, playsSound: true)
    static let hidden = NotificationPermission.allowed(showsOnScreen: false, playsSound: true)
    static let soundOff = NotificationPermission.allowed(showsOnScreen: true, playsSound: false)
    static let hiddenAndSoundOff = NotificationPermission.allowed(showsOnScreen: false, playsSound: false)

    // MARK: Status line

    /// One line at a time, in this priority: denied, not on screen, sound off, not answered. Sound off counts
    /// only while Play sound is on, since Join! itself sends a silent notification then.
    @Test(arguments: [
        ("not answered", NotificationPermission.notDetermined, true, NotificationStatus.notAnswered),
        ("not answered, Play sound off", .notDetermined, false, .notAnswered),
        ("denied", .denied, true, .denied),
        ("allowed", allowed, true, nil),
        ("never on screen", hidden, true, .notOnScreen),
        ("macOS's sound off", soundOff, true, .soundOff),
        ("macOS's sound off, Play sound off", soundOff, false, nil),
        ("never on screen, sound off: on screen first", hiddenAndSoundOff, true, .notOnScreen),
        ("never on screen, Play sound off", hiddenAndSoundOff, false, .notOnScreen),
    ] as [(String, NotificationPermission, Bool, NotificationStatus?)])
    func theLineWhileNotifyMeHasATime(_ name: String, permission: NotificationPermission, playsSound: Bool, expected: NotificationStatus?) {
        #expect(NotificationStatus.current(notificationsEnabled: true, playsSound: playsSound, permission: permission) == expected)
    }

    /// Hidden while Notify me is Never, whatever macOS says: no hint before the user opts in.
    @Test(arguments: [NotificationPermission.notDetermined, .denied, allowed, hidden, soundOff, hiddenAndSoundOff])
    func noLineWhileNotifyMeIsNever(_ permission: NotificationPermission) {
        #expect(NotificationStatus.current(notificationsEnabled: false, playsSound: true, permission: permission) == nil)
    }

    /// The order of `allCases` is the priority.
    @Test func thePriority() {
        #expect(NotificationStatus.allCases == [.denied, .notOnScreen, .soundOff, .notAnswered])
    }

    /// Each line names System Settings › Notifications, and none names macOS's style options. Orange when no
    /// notification reaches the screen.
    @Test(arguments: [
        (NotificationStatus.denied, "Allow notifications for Join! in System Settings › Notifications.", true),
        (.notOnScreen, "Show Join!'s notifications on screen in System Settings › Notifications.", true),
        (.soundOff, "Turn on sound for Join! in System Settings › Notifications.", false),
        (.notAnswered, "Allow notifications from Join! when macOS asks, or in System Settings › Notifications.", false),
    ])
    func theLines(_ status: NotificationStatus, text: String, isWarning: Bool) {
        #expect(status.text == text)
        #expect(status.isWarning == isWarning)
        for style in ["Banner", "Alerts", "Temporary", "Persistent"] {
            #expect(!status.text.contains(style))
        }
    }

    /// Open System Settings goes to Notifications › Join!, falling back to the Notifications pane.
    @Test func openSystemSettings() {
        #expect(NotificationStatus.openSettingsTitle == "Open System Settings")
        #expect(NotificationStatus.settingsURLs().map(\.absoluteString) == [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.poliuk.join",
            "x-apple.systempreferences:com.apple.preference.notifications",
        ])
    }

    // MARK: From macOS's settings

    /// Not on screen when its alerts are off or their style is None, and always in the quiet provisional mode;
    /// macOS's own sound switch is carried as it is.
    @Test(arguments: [
        ("never asked", NotificationPermission.Authorization.notDetermined, true, true, NotificationPermission.notDetermined),
        ("denied", .denied, true, true, .denied),
        ("denied, nothing on", .denied, false, false, .denied),
        ("allowed", .authorized, true, true, allowed),
        ("allowed, style None", .authorized, false, true, hidden),
        ("allowed, sound off", .authorized, true, false, soundOff),
        ("allowed, style None, sound off", .authorized, false, false, hiddenAndSoundOff),
        ("provisional", .provisional, true, true, hidden),
        ("provisional, sound off", .provisional, true, false, hiddenAndSoundOff),
    ] as [(String, NotificationPermission.Authorization, Bool, Bool, NotificationPermission)])
    func fromMacOSSettings(_ name: String, authorization: NotificationPermission.Authorization, alertsShown: Bool, soundOn: Bool, expected: NotificationPermission) {
        #expect(NotificationPermission(authorization: authorization, alertsShown: alertsShown, soundOn: soundOn) == expected)
    }

    // MARK: Asking

    /// Join! asks only while nothing is decided: macOS prompts once.
    @Test(arguments: [
        (NotificationPermission.notDetermined, true),
        (.denied, false),
        (allowed, false),
        (hidden, false),
        (soundOff, false),
    ])
    func asking(_ permission: NotificationPermission, needsAsking: Bool) {
        #expect(permission.needsAsking == needsAsking)
    }

    // MARK: Fixture runs

    /// JOIN_FIXTURE_NOTIFICATIONS picks a fixture run's permission, so every line can be snapshotted; anything
    /// else is a Mac that has never run Join!.
    @Test(arguments: [
        ("notDetermined", NotificationPermission.notDetermined),
        ("denied", .denied),
        ("hidden", hidden),
        ("soundOff", soundOff),
        ("authorized", allowed),
        ("Denied", .notDetermined),
        ("", .notDetermined),
        (nil, .notDetermined),
    ] as [(String?, NotificationPermission)])
    func fixturePermission(_ value: String?, expected: NotificationPermission) {
        #expect(NotificationPermission.fixture(value) == expected)
    }

    @Test func theFixtureVariable() {
        #expect(NotificationPermission.fixtureVariable == "JOIN_FIXTURE_NOTIFICATIONS")
    }

    // MARK: Send Demo Notification

    /// It works unless notifications are denied, and never in a fixture run, which never touches the real
    /// notification center; the help tag says why.
    @Test(arguments: [
        ("not answered: the first click asks", NotificationPermission.notDetermined, false, true, "Sends a notification with a sample event."),
        ("allowed", allowed, false, true, "Sends a notification with a sample event."),
        ("never on screen", hidden, false, true, "Sends a notification with a sample event."),
        ("denied", .denied, false, false, "Allow notifications for Join! in System Settings first."),
        ("a fixture run", allowed, true, false, "Not available in fixture mode."),
        ("a fixture run, denied", .denied, true, false, "Not available in fixture mode."),
    ] as [(String, NotificationPermission, Bool, Bool, String)])
    func sendDemoNotification(_ name: String, permission: NotificationPermission, isFixture: Bool, isEnabled: Bool, help: String) {
        let button = SendDemoNotificationButton(permission: permission, isFixture: isFixture)
        #expect(button.isEnabled == isEnabled)
        #expect(button.help == help)
        #expect(SendDemoNotificationButton.title == "Send Demo Notification")
    }
}
