import AppKit
import Observation
import JoinCore

/// Owns the app's long-lived objects and wires them together.
@MainActor
@Observable
final class AppModel {
    let preferences: Preferences
    let meetingStore: MeetingStore
    let alertCoordinator: AlertCoordinator

    /// Advances every 30 seconds so the menu bar text and list rows stay fresh.
    private(set) var now = Date()
    @ObservationIgnored private var ticker: Timer?

    init() {
        let preferences = Preferences()
        let store = MeetingStore(service: EventKitCalendarService(), preferences: preferences)
        self.preferences = preferences
        self.meetingStore = store
        self.alertCoordinator = AlertCoordinator(store: store, preferences: preferences, windows: AlertWindowController())
    }

    func start() {
        Task { await meetingStore.start() }
        alertCoordinator.start()

        ticker = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.now = Date() }
        }
        ticker?.tolerance = 5

        observeChanges(of: { [preferences] in
            _ = preferences.enabledCalendarIDs
            _ = preferences.outOfOfficeKeywords
        }) { [weak self] in
            self?.meetingStore.refresh()
        }
        observeChanges(of: { [preferences] in _ = preferences.leadTime }) { [weak self] in
            self?.alertCoordinator.replan()
        }
        observeChanges(of: { [meetingStore] in _ = meetingStore.meetings }) { [weak self] in
            self?.now = Date()
        }
    }

    var menuBarTitle: String? {
        guard preferences.menuBarShowsNextEvent else { return nil }
        let meeting = meetingStore.current(at: now) ?? meetingStore.next(at: now)
        return MeetingTimeFormatter.menuBarTitle(for: meeting, now: now)
    }

    func join(_ meeting: Meeting) {
        guard let url = meeting.joinURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// The SDK this builds against has no `openSettings` environment action, and `SettingsLink`
    /// does nothing from inside a MenuBarExtra window, so send the responder-chain action directly.
    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.windows.first { $0.title.contains("Settings") || $0.identifier?.rawValue.contains("Settings") == true }?
            .makeKeyAndOrderFront(nil)
    }

    func openCalendarPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
