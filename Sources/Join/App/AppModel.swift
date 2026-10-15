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
    let updateChecker: UpdateChecker

    /// Advances on every half minute of the clock so countdowns in the menu bar and panel stay fresh.
    private(set) var now = Date()
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private let settingsWindow = SettingsWindowController()
    /// Closes the menu bar panel; set by the status item controller.
    @ObservationIgnored var closePanel: (() -> Void)?

    /// Set when running with a fake calendar (see FixtureCalendarService).
    let isFixture: Bool
    /// Fixture runs only (the `panelFrost` hook): a frost opacity to try on the real panel; nil keeps the palette's.
    var panelFrostOverride: Double?

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
        self.updateChecker = UpdateChecker(preferences: preferences, fixtureScenario: fixture)
    }

    func start() {
        Task { await meetingStore.start() }
        if !isFixture { alertCoordinator.start() }

        // Ticking on :00 and :30 keeps "in 4 min" in step with meetings, which start on whole minutes.
        let interval: TimeInterval = 30
        let firstTick = Date(timeIntervalSinceReferenceDate: (Date().timeIntervalSinceReferenceDate / interval).rounded(.up) * interval)
        let ticker = Timer(fire: firstTick, interval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                now = Date()
                updateChecker.tick(now: now)
            }
        }
        ticker.tolerance = 1
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker

        // The daily update check: at launch, on the ticks above and on wake, whenever it's due. At launch
        // also when the last check offered an update, to bring the offer back.
        updateChecker.start(now: Date())
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateChecker.tick(now: Date()) }
        }

        observeChanges(of: { [preferences] in
            _ = preferences.enabledCalendarIDs
            _ = preferences.eventsWithoutParticipants
            _ = preferences.outOfOfficeEvents
            _ = preferences.outOfOfficeKeywords
        }) { [weak self] in
            self?.meetingStore.refresh()
        }
        // Never (alerts off) cancels pending alerts but leaves one already on screen; a time brings them back.
        observeChanges(of: { [preferences] in
            _ = preferences.leadTime
            _ = preferences.fullScreenAlertsEnabled
        }) { [weak self] in
            self?.alertCoordinator.replan()
        }
        observeChanges(of: { [meetingStore] in _ = meetingStore.meetings }) { [weak self] in
            self?.now = Date()
        }
        // Turning automatic checks back on checks straight away when one is due.
        observeChanges(of: { [preferences] in _ = preferences.checksForUpdates }) { [weak self] in
            self?.updateChecker.tick(now: Date())
        }
    }

    var menuBarStatus: MenuBarStatus {
        MenuBarPresenter.status(
            meetings: meetingStore.alertableMeetings,
            now: now,
            pauseState: alertCoordinator.pauseState,
            showsNextEvent: preferences.menuBarShowsNextEvent,
            showsTitles: preferences.menuBarShowsEventTitles,
            startingSoonWindow: preferences.startingSoonPill.window
        )
    }

    var panelContent: PanelContent {
        PanelPresenter.content(
            meetings: meetingStore.meetings,
            alertable: meetingStore.alertableMeetings,
            dismissed: meetingStore.dismissedMeetingIDs,
            now: now,
            startingSoonWindow: preferences.startingSoonPill.window
        )
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

    /// The card's close button and a row's Dismiss: no full-screen alert for this occurrence, and the menu
    /// bar item and the card move on to what comes next. The panel stays open and lists it as dismissed
    /// until it ends. Only a meeting that may alert can be dismissed; anything else is left alone.
    func dismiss(_ meeting: Meeting) {
        guard meetingStore.alertableMeetings.contains(where: { $0.id == meeting.id }) else { return }
        updateDismissedEvents(preferences.dismissedEvents.dismissing(meeting))
    }

    /// A dismissed row's Restore: the menu bar item and the card take the meeting back, and its full-screen
    /// alert comes at once if it's still due (the scheduler's usual late grace and snooze rules).
    func restore(_ meeting: Meeting) {
        updateDismissedEvents(preferences.dismissedEvents.restoring(meeting.id))
    }

    /// The alert coordinator, the menu bar item and the panel all follow `MeetingStore.alertableMeetings`,
    /// which reads the dismissed events, so this one write updates all three.
    private func updateDismissedEvents(_ events: DismissedEvents) {
        let date = Date()
        // Pruned as it's written, so entries for events that are over don't wait for the next calendar read.
        let pruned = events.pruned(at: date, meetings: meetingStore.meetings)
        // Fresh countdowns for whatever takes the card and the menu bar.
        now = date
        guard pruned != preferences.dismissedEvents else { return }
        preferences.dismissedEvents = pruned
    }

    /// The update bar's button: Install, Download Page after a failed install, Show in Finder once the
    /// new copy waits in a folder.
    func performUpdateAction() {
        guard let update = updateChecker.offeredUpdate else { return }
        switch updateChecker.install {
        case .idle:
            updateChecker.installUpdate()
        case .failed:
            closePanel?()
            NSWorkspace.shared.open(update.pageURL)
        case .revealed(let app):
            // Once the user has moved the new copy, there's nothing to show: the bar offers Install again.
            guard FileManager.default.fileExists(atPath: app.path) else {
                updateChecker.forgetRevealedCopy()
                return
            }
            closePanel?()
            NSWorkspace.shared.activateFileViewerSelecting([app])
        case .downloading, .installing:
            break
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
