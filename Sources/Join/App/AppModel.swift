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
    /// The menu bar panel's Today / All filter, remembered while the app runs.
    var panelShowsTodayOnly = true
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private let settingsWindow = SettingsWindowController()
    /// Closes the menu bar panel; set by the status item controller.
    @ObservationIgnored var closePanel: (() -> Void)?

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

    func refreshNow() {
        now = Date()
    }

    func join(_ meeting: Meeting) {
        guard let url = meeting.joinURL else { return }
        closePanel?()
        NSWorkspace.shared.open(url)
    }

    func openSettings(pane: SettingsPane? = nil) {
        closePanel?()
        settingsWindow.show(model: self, pane: pane)
    }

    func openCalendarPrivacySettings() {
        closePanel?()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
