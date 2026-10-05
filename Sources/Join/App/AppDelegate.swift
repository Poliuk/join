import AppKit
import JoinCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusItem: StatusItemController?
    private var hookObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.start()
        let statusItem = StatusItemController(model: model)
        model.closePanel = { [weak statusItem] in statusItem?.close() }
        self.statusItem = statusItem
        observeScriptHooks()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.openSettings()
        return false
    }

    /// Distributed notifications that let scripts drive the app during development and testing.
    /// The notification's object, when present, is the argument (e.g. a Settings pane or a folder).
    private func observeScriptHooks() {
        let hooks: [(String, @MainActor (AppDelegate, String?) -> Void)] = [
            ("openSettings", { delegate, argument in delegate.model.openSettings(pane: argument.flatMap(SettingsPane.init(rawValue:))) }),
            ("snapshot", { _, argument in WindowSnapshots.write(to: argument ?? NSTemporaryDirectory()) }),
            ("showDemoAlert", { delegate, _ in delegate.model.alertCoordinator.showDemoAlert() }),
            ("togglePanel", { delegate, _ in delegate.statusItem?.toggle() }),
            ("dismissAlert", { delegate, _ in delegate.model.alertCoordinator.dismiss() }),
            ("pause", { delegate, argument in
                delegate.model.alertCoordinator.pause(argument.flatMap(PauseOption.init(rawValue:)) ?? .untilResumed)
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
                forName: Notification.Name("com.poliuk.join." + name), object: nil, queue: .main
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
