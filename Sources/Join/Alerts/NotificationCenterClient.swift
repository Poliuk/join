import Foundation
import OSLog
import UserNotifications
import JoinCore

/// macOS's notification center, as the notification coordinator uses it: what Join! may do, asking for it,
/// the categories, posting and withdrawing. Nonisolated, returning only `Sendable` values: UserNotifications
/// has no `Sendable` annotations and calls back on its own queue, so its objects never leave the
/// implementation. `SystemNotificationCenter` is the real one; `FixtureNotificationCenter` stands in for it in
/// a fixture run, which shares the app's bundle id and so must never touch the real one; and
/// `UnavailableNotificationCenter` in a build without an app bundle, where the real one can't be used.
nonisolated protocol NotificationCenterClient: Sendable {
    /// What macOS lets Join!'s notifications do now. It reports no changes, so this is read again when Join!
    /// becomes active and when Settings becomes key.
    func permission() async -> NotificationPermission
    /// Asks macOS, which prompts only while nothing is decided and otherwise answers with the stored choice,
    /// then reads the permission again. Alert and sound, with a link back from System Settings to the Alerts
    /// pane; no badge (Join! has no Dock icon) and no quiet provisional mode.
    func requestPermission() async -> NotificationPermission
    /// Registers every category (`NotificationCategory.all`) with its actions for these snooze durations,
    /// replacing the whole set: at launch, and whenever the durations change.
    func registerCategories(snoozeDurations: SnoozeDurations)
    /// Delivers `content` now: Join! posts each notification when it's due and schedules nothing ahead. Posting
    /// under an identifier already delivered replaces that notification and moves it to the top.
    func post(_ content: NotificationContent) async throws
    /// The identifiers of Join!'s notifications still on screen or in Notification Center.
    func deliveredIdentifiers() async -> [String]
    /// Removes these notifications, delivered or still pending.
    func withdraw(_ identifiers: [String])
    /// Sends the responses to `responder` (macOS keeps it weakly). Before launch finishes, so a click that
    /// launched Join! isn't lost.
    func setResponder(_ responder: NotificationResponder)
}

/// The real notification center. It's asked for afresh on each call, since `UNUserNotificationCenter`
/// isn't `Sendable`; only a process with an app bundle may use it, so `AppModel` uses it only inside one, and
/// `swift test` and `swift run` never get here.
nonisolated struct SystemNotificationCenter: NotificationCenterClient {
    private var center: UNUserNotificationCenter { .current() }

    func permission() async -> NotificationPermission {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: Self.permission(from: settings))
            }
        }
    }

    func requestPermission() async -> NotificationPermission {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .providesAppNotificationSettings])
        } catch {
            // UNErrorDomain and a code: nothing personal.
            Logger.notifications.error("Asking to send notifications failed: \(String(describing: error), privacy: .public)")
        }
        return await permission()
    }

    func registerCategories(snoozeDurations: SnoozeDurations) {
        let categories = NotificationCategory.all.map { category in
            UNNotificationCategory(
                identifier: category.identifier,
                // None brings Join! to the front: Join opens the link from the background, as the full-screen
                // alert's Join does while Join! isn't active.
                actions: category.actions(snoozeDurations: snoozeDurations).map { action in
                    UNNotificationAction(identifier: action.identifier, title: action.title, options: [])
                },
                intentIdentifiers: [],
                // No custom dismiss action: macOS's close button only closes it. Previews follow the user's
                // Show previews setting.
                options: []
            )
        }
        center.setNotificationCategories(Set(categories))
    }

    func post(_ content: NotificationContent) async throws {
        let notification = UNMutableNotificationContent()
        notification.title = content.title
        notification.subtitle = content.subtitle
        notification.body = content.body
        notification.categoryIdentifier = content.category.identifier
        notification.threadIdentifier = NotificationContent.threadIdentifier
        notification.userInfo = content.payload.userInfo
        notification.sound = content.playsSound ? .default : nil
        // Never Time Sensitive: that needs an entitlement an ad-hoc-signed build can't carry.
        notification.interruptionLevel = .active
        // No trigger: delivered now.
        let request = UNNotificationRequest(identifier: content.identifier.rawValue, content: notification, trigger: nil)
        try await center.add(request)
    }

    func deliveredIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications.map(\.request.identifier))
            }
        }
    }

    func withdraw(_ identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func setResponder(_ responder: NotificationResponder) {
        center.delegate = responder
    }

    /// Join!'s permission from macOS's settings (`NotificationPermission.init(authorization:alertsShown:soundOn:)`).
    private static func permission(from settings: UNNotificationSettings) -> NotificationPermission {
        let authorization: NotificationPermission.Authorization
        switch settings.authorizationStatus {
        case .notDetermined: authorization = .notDetermined
        case .denied: authorization = .denied
        case .authorized: authorization = .authorized
        case .provisional: authorization = .provisional
        // A status macOS adds later: read as allowed, by what its settings say.
        @unknown default: authorization = .authorized
        }
        // Only a switch the user turned off counts as off, so an unsupported one never brings a status line.
        return NotificationPermission(
            authorization: authorization,
            alertsShown: settings.alertSetting != .disabled && settings.alertStyle != .none,
            soundOn: settings.soundSetting != .disabled
        )
    }
}

/// The notification center in a fixture run: the permission comes from JOIN_FIXTURE_NOTIFICATIONS
/// (`NotificationPermission.fixture`) and stays as it is, so every status line can be snapshotted; asking
/// changes nothing, as when macOS's prompt goes unanswered. Nothing reaches macOS: what would be asked, sent
/// or removed is logged, and nothing is ever delivered.
nonisolated struct FixtureNotificationCenter: NotificationCenterClient {
    private let fixedPermission: NotificationPermission

    init(permission: NotificationPermission) {
        fixedPermission = permission
    }

    /// This run's permission, from the environment.
    static var environmentPermission: NotificationPermission {
        NotificationPermission.fixture(ProcessInfo.processInfo.environment[NotificationPermission.fixtureVariable])
    }

    func permission() async -> NotificationPermission {
        fixedPermission
    }

    func requestPermission() async -> NotificationPermission {
        Logger.fixture.notice("Fixture: would ask macOS to send notifications; the permission stays \(String(describing: fixedPermission), privacy: .public)")
        return fixedPermission
    }

    func registerCategories(snoozeDurations: SnoozeDurations) {
        // Settings, not calendar data.
        Logger.fixture.notice("Fixture: would register the notification categories for snoozes of \(snoozeDurations.all, privacy: .public) s")
    }

    func post(_ content: NotificationContent) async throws {
        // A fixture's events are made up, so their titles and ids aren't personal.
        Logger.fixture.notice("Fixture: would send \(content.identifier.rawValue, privacy: .public), \"\(content.title, privacy: .public)\", category \(content.category.identifier, privacy: .public), sound \(content.playsSound, privacy: .public)")
    }

    func deliveredIdentifiers() async -> [String] {
        []
    }

    func withdraw(_ identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        Logger.fixture.notice("Fixture: would withdraw \(identifiers, privacy: .public)")
    }

    func setResponder(_ responder: NotificationResponder) {
        Logger.fixture.notice("Fixture: notification responses stay with the real app; no responder set")
    }
}

/// The notification center in a build without an app bundle (`swift run`, `.build/debug/Join`):
/// `UNUserNotificationCenter` raises without one, so, like the update checker, such a build has no
/// notifications. Never allowed; nothing is asked, sent or removed, and nothing is logged.
nonisolated struct UnavailableNotificationCenter: NotificationCenterClient {
    func permission() async -> NotificationPermission { .denied }
    func requestPermission() async -> NotificationPermission { .denied }
    func registerCategories(snoozeDurations: SnoozeDurations) {}
    func post(_ content: NotificationContent) async throws {}
    func deliveredIdentifiers() async -> [String] { [] }
    func withdraw(_ identifiers: [String]) {}
    func setResponder(_ responder: NotificationResponder) {}
}
