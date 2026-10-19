import AppKit
import JoinCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: StatusItemController?
    private var hookObservers: [NSObjectProtocol] = []
    private var fixtureExpiry: Timer?

    /// A forgotten fixture instance would leave the user without real alerts, so it quits on its own.
    private static let fixtureLifetime: TimeInterval = 2 * 60 * 60
    private static let hookPrefix = "com.poliuk.join.fixture."

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A fixture run can ask for a Dock icon (JOIN_FIXTURE_REGULAR=1) so UI automation tools can target it.
        let regular = model.isFixture && ProcessInfo.processInfo.environment["JOIN_FIXTURE_REGULAR"] == "1"
        NSApp.setActivationPolicy(regular ? .regular : .accessory)
        model.start()
        let statusItem = StatusItemController(model: model)
        model.closePanel = { [weak statusItem] in statusItem?.close() }
        model.alertCoordinator.willPresentAlert = { [weak statusItem] in statusItem?.close() }
        self.statusItem = statusItem
        if model.isFixture {
            observeScriptHooks()
            fixtureExpiry = Timer.scheduledTimer(withTimeInterval: Self.fixtureLifetime, repeats: false) { _ in
                MainActor.assumeIsolated { NSApp.terminate(nil) }
            }
        }
    }

    /// Quitting without Install and Relaunch installs nothing: a downloaded update goes, and the next
    /// launch offers it again.
    func applicationWillTerminate(_ notification: Notification) {
        model.updateChecker.discardDownload()
    }

    /// Opening Join! again (from Finder, say) opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.openSettings()
        return false
    }

    /// Distributed notifications that let scripts drive a fixture run (see FixtureCalendarService).
    /// They are never registered in a normal run, so no other process can pause, dismiss or capture
    /// the real app. The notification's object, when present, is the argument.
    private func observeScriptHooks() {
        let hooks: [(String, @MainActor (AppDelegate, String?) -> Void)] = [
            // A pane's raw value, or fullScreenAlert, the Alerts pane's until 1.3.0 (`SettingsPane(hookArgument:)`).
            ("openSettings", { delegate, argument in delegate.model.openSettings(pane: argument.flatMap(SettingsPane.init(hookArgument:))) }),
            ("snapshot", { _, argument in WindowSnapshots.write(named: argument) }),
            // What Test Full-Screen Alert does (Show Demo until 2026-10-19; the hook kept its name).
            ("showDemoAlert", { delegate, _ in delegate.model.alertCoordinator.showDemoAlert() }),
            // What Test Notification does: the demo event's card, which the `snapshot` hook captures with the rest.
            ("showTestNotification", { delegate, _ in delegate.model.notificationCoordinator.showTestNotification() }),
            ("togglePanel", { delegate, _ in delegate.statusItem?.toggle() }),
            ("dismissAlert", { delegate, _ in delegate.model.alertCoordinator.dismiss() }),
            ("pause", { delegate, argument in
                guard let option = argument.flatMap(PauseOption.init(rawValue:)) else { return }
                delegate.model.alertCoordinator.pause(option)
            }),
            ("resume", { delegate, _ in delegate.model.alertCoordinator.resume() }),
            ("preset", { delegate, argument in
                guard let preset = AlertAppearancePreset.allCases.first(where: { "\($0)" == argument }) else { return }
                delegate.model.preferences.appearance = preset.appearance
            }),
            ("panelFilter", { delegate, argument in
                guard let filter = argument.flatMap(PanelListFilter.init(rawValue:)) else { return }
                delegate.model.preferences.panelListFilter = filter
            }),
            // Dismiss or restore an event as the panel's buttons do, or as a repeating event's menu does with
            // This Event and All Future Events; the argument names it (`listedMeeting`).
            ("dismissEvent", { delegate, argument in
                guard let meeting = delegate.listedMeeting(matching: argument) else { return }
                delegate.model.dismiss(meeting)
            }),
            ("restoreEvent", { delegate, argument in
                guard let meeting = delegate.listedMeeting(matching: argument) else { return }
                delegate.model.restore(meeting)
            }),
            ("dismissFutureEvents", { delegate, argument in
                guard let meeting = delegate.listedMeeting(matching: argument) else { return }
                delegate.model.dismiss(meeting, scope: .allFutureEvents)
            }),
            ("restoreFutureEvents", { delegate, argument in
                guard let meeting = delegate.listedMeeting(matching: argument) else { return }
                delegate.model.restore(meeting, scope: .allFutureEvents)
            }),
            ("panelFrost", { delegate, argument in
                // An opacity from 0 to 1 to try on the real panel; anything else goes back to the palette's.
                delegate.model.panelFrostOverride = argument.flatMap(Double.init).flatMap { (0...1).contains($0) ? $0 : nil }
            }),
            // Against the fixture feed (JOIN_FIXTURE_UPDATE); installing only does anything with =ready (a
            // pretend download, then a relaunch as the same fixture) or =live.
            ("checkForUpdates", { delegate, _ in delegate.model.updateChecker.checkNow() }),
            ("installUpdate", { delegate, _ in delegate.model.updateChecker.installUpdate() }),
            ("installAndRelaunch", { delegate, _ in delegate.model.updateChecker.installAndRelaunch() }),
            ("appearance", { _, argument in
                switch argument {
                case "light": NSApp.appearance = NSAppearance(named: .aqua)
                case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
                default: NSApp.appearance = nil
                }
            }),
        ]
        for (name, action) in hooks {
            let observer = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(Self.hookPrefix + name), object: nil, queue: .main
            ) { [weak self] notification in
                let argument = notification.object as? String
                MainActor.assumeIsolated {
                    guard let self else { return }
                    action(self, argument)
                }
            }
            hookObservers.append(observer)
        }
    }

    /// The meeting a hook's argument names, among those shown that haven't ended: by full id, else by the
    /// id before "@" (a fixture's "workshop"), else by exact title; the first in time order.
    private func listedMeeting(matching argument: String?) -> Meeting? {
        guard let argument, !argument.isEmpty else { return nil }
        let now = Date()
        let listed = model.meetingStore.meetings
            .filter { !$0.hasEnded(at: now) }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
        return listed.first { $0.id == argument }
            ?? listed.first { String($0.id.prefix { $0 != "@" }) == argument }
            ?? listed.first { $0.title == argument }
    }
}
