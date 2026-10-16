import Foundation
import os
import UserNotifications
import JoinCore

/// What the user did with one of Join!'s notifications, read off macOS's response on its own queue, so only
/// `Sendable` values reach the main actor.
struct NotificationReply: Sendable {
    /// Whose notification it was: a meeting's or the demo's; nil for one Join! didn't make.
    let identifier: NotificationIdentifier?
    /// Join, a snooze or At event start; nil for a click on the notification itself, which does nothing (the
    /// user's choice, 2026-10-16), or anything else macOS reports.
    let response: AlertResponse?
    /// The meeting's id, link and times, which a response needs before the calendar is read (a click can
    /// launch Join!); nil for a notification that carries none.
    let payload: NotificationPayload?
}

/// The notification center's delegate. Nonisolated: macOS calls it on its own queue, not the main thread, so a
/// main-actor conformance would trap. It answers the presentation question at once, records when a response
/// arrived (for `ignoresReopen`), reads the response into a `NotificationReply` and hops to the main actor to
/// handle it, returning only after the handling, which is when macOS gets its completion call.
nonisolated final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let onReply: @MainActor @Sendable (NotificationReply) -> Void
    private let onOpenSettings: @MainActor @Sendable () -> Void
    /// Written on macOS's queue as a response arrives, read on the main thread by the reopen handler, which
    /// may run before the reply's hop to the main actor does.
    private let lastResponseDate = OSAllocatedUnfairLock<Date?>(initialState: nil)

    /// `onReply` handles every response; `onOpenSettings` is System Settings › Notifications › Join!'s link
    /// back to Join!'s settings.
    init(
        onReply: @escaping @MainActor @Sendable (NotificationReply) -> Void,
        onOpenSettings: @escaping @MainActor @Sendable () -> Void
    ) {
        self.onReply = onReply
        self.onOpenSettings = onOpenSettings
    }

    /// When the last response arrived, a click on the notification itself included.
    var lastResponse: Date? {
        lastResponseDate.withLock { $0 }
    }

    /// A notification that's due while Join! is active (Settings or the full-screen alert in front) shows all
    /// the same, with its sound when it has one.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        lastResponseDate.withLock { $0 = Date() }
        let request = response.notification.request
        let reply = NotificationReply(
            identifier: NotificationIdentifier(rawValue: request.identifier),
            response: AlertResponse(notificationActionIdentifier: response.actionIdentifier),
            payload: NotificationPayload(userInfo: request.content.userInfo)
        )
        await onReply(reply)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        Task { @MainActor [onOpenSettings] in onOpenSettings() }
    }
}
