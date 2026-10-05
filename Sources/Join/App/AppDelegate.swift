import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    private var openSettingsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.start()
        observeOpenSettingsRequests()
    }

    /// Lets scripts open Settings: `distributednotify com.poliuk.join.openSettings` or any poster of that name.
    private func observeOpenSettingsRequests() {
        openSettingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.poliuk.join.openSettings"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.model.openSettings() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.openSettings()
        return false
    }
}
