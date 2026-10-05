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

    /// Advances on every half minute of the clock so countdowns in the menu bar and panel stay fresh.
    private(set) var now = Date()
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private let settingsWindow = SettingsWindowController()
    /// Closes the menu bar panel; set by the status item controller.
    @ObservationIgnored var closePanel: (() -> Void)?

    /// Set when running with a fake calendar (see FixtureCalendarService).
    let isFixture: Bool

    init() {
        let fixture = FixtureCalendarService.scenario
        let defaults = fixture.flatMap { _ in UserDefaults(suiteName: FixtureCalendarService.defaultsSuite) } ?? .standard
        let service: CalendarService = fixture.map { FixtureCalendarService(scenario: $0) } ?? EventKitCalendarService()
        let preferences = Preferences(defaults: defaults)
        let store = MeetingStore(service: service, preferences: preferences)
        self.isFixture = fixture != nil
        self.preferences = preferences
        self.meetingStore = store
        self.alertCoordinator = AlertCoordinator(store: store, preferences: preferences, windows: AlertWindowController(), defaults: defaults)
    }

    func start() {
        Task { await meetingStore.start() }
        if !isFixture { alertCoordinator.start() }

        // Ticking on :00 and :30 keeps "in 4 min" in step with meetings, which start on whole minutes.
        let interval: TimeInterval = 30
        let firstTick = Date(timeIntervalSinceReferenceDate: (Date().timeIntervalSinceReferenceDate / interval).rounded(.up) * interval)
        let ticker = Timer(fire: firstTick, interval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.now = Date() }
        }
        ticker.tolerance = 1
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker

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

    var menuBarStatus: MenuBarStatus {
        MenuBarPresenter.status(
            meetings: meetingStore.alertableMeetings,
            now: now,
            pauseState: alertCoordinator.pauseState,
            showsNextEvent: preferences.menuBarShowsNextEvent,
            showsTitles: preferences.menuBarShowsEventTitles
        )
    }

    var panelContent: PanelContent {
        PanelPresenter.content(meetings: meetingStore.meetings, alertable: meetingStore.alertableMeetings, now: now)
    }

    var pausedMessage: String? {
        MenuBarPresenter.pausedMessage(alertCoordinator.pauseState, now: now)
    }

    var isPaused: Bool {
        alertCoordinator.pauseState.isPaused(at: now)
    }

    func refreshNow() {
        now = Date()
    }

    func join(_ meeting: Meeting) {
        guard let url = meeting.joinURL else { return }
        closePanel?()
        NSWorkspace.shared.open(url)
    }

    func perform(_ action: PanelAction) {
        closePanel?()
        switch action {
        case .join(let url), .directions(let url):
            NSWorkspace.shared.open(url)
        }
    }

    func pause(_ option: PauseOption) {
        alertCoordinator.pause(option)
    }

    func resume() {
        alertCoordinator.resume()
    }

    func openSettings(pane: SettingsPane? = nil) {
        closePanel?()
        settingsWindow.show(model: self, pane: pane)
    }

    func openCalendar() {
        closePanel?()
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
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
