import AppKit
import JoinCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusItem: StatusItemController?
    private var hookObservers: [NSObjectProtocol] = []
    private var fixtureExpiry: Timer?

    /// A forgotten fixture instance would leave the user without real alerts, so it quits on its own.
    static let fixtureLifetime: TimeInterval = 2 * 60 * 60
    static let hookPrefix = "com.poliuk.join.fixture."

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.start()
        let statusItem = StatusItemController(model: model)
        model.closePanel = { [weak statusItem] in statusItem?.close() }
        self.statusItem = statusItem
        if model.isFixture {
            observeScriptHooks()
            fixtureExpiry = Timer.scheduledTimer(withTimeInterval: Self.fixtureLifetime, repeats: false) { _ in
                Task { @MainActor in NSApp.terminate(nil) }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.openSettings()
        return false
    }

    /// Distributed notifications that let scripts drive a fixture run (see FixtureCalendarService).
    /// They are never registered in a normal run, so no other process can pause, dismiss or capture
    /// the real app. The notification's object, when present, is the argument.
    private func observeScriptHooks() {
        let hooks: [(String, @MainActor (AppDelegate, String?) -> Void)] = [
            ("openSettings", { delegate, argument in delegate.model.openSettings(pane: argument.flatMap(SettingsPane.init(rawValue:))) }),
            ("snapshot", { _, argument in WindowSnapshots.write(named: argument) }),
            ("showDemoAlert", { delegate, _ in delegate.model.alertCoordinator.showDemoAlert() }),
            ("togglePanel", { delegate, _ in delegate.statusItem?.toggle() }),
            ("dismissAlert", { delegate, _ in delegate.model.alertCoordinator.dismiss() }),
            ("pause", { delegate, argument in
                guard let option = argument.flatMap(PauseOption.init(rawValue:)) else { return }
                delegate.model.alertCoordinator.pause(option)
            }),
            ("resume", { delegate, _ in delegate.model.alertCoordinator.resume() }),
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
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    action(self, argument)
                }
            }
            hookObservers.append(observer)
        }
    }
}
