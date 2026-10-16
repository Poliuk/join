import AppKit
import Observation
import OSLog
import JoinCore

/// Owns the app's long-lived objects and wires them together.
@Observable
final class AppModel {
    let preferences: Preferences
    let meetingStore: MeetingStore
    let alertCoordinator: AlertCoordinator
    let notificationCoordinator: NotificationCoordinator
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
        let defaults: UserDefaults
        let service: CalendarService
        let notificationCenter: any NotificationCenterClient
        if let fixture {
            // Never `.standard`: a fixture run must not change real settings. Only the app's own bundle id or
            // the global domain would make this nil.
            guard let fixtureDefaults = UserDefaults(suiteName: FixtureCalendarService.defaultsSuite) else {
                preconditionFailure("A fixture run needs its own defaults domain")
            }
            defaults = fixtureDefaults
            service = FixtureCalendarService(scenario: fixture)
            // Same bundle id as the real app, so never the real notification center: no prompt, no posting, no
            // responder, no removal.
            notificationCenter = FixtureNotificationCenter(permission: FixtureNotificationCenter.environmentPermission)
        } else {
            defaults = .standard
            service = EventKitCalendarService()
            notificationCenter = SystemNotificationCenter()
        }
        let preferences = Preferences(defaults: defaults)
        if fixture != nil, preferences.dismissedEvents.withoutSeriesRules != preferences.dismissedEvents {
            // A fixture's series ids ("workshop", "planning", "rev") are the same every launch, and a rule for all
            // future events never expires, so it would dismiss every later run's occurrences: each fixture launch
            // starts without rules, and without the exceptions that only matter inside one.
            preferences.dismissedEvents = preferences.dismissedEvents.withoutSeriesRules
        }
        let store = MeetingStore(service: service, preferences: preferences)
        self.isFixture = fixture != nil
        self.preferences = preferences
        self.meetingStore = store
        let alertCoordinator = AlertCoordinator(store: store, preferences: preferences, windows: AlertWindowController(), defaults: defaults)
        let notificationCoordinator = NotificationCoordinator(
            center: notificationCenter,
            store: store,
            preferences: preferences,
            alerts: alertCoordinator,
            defaults: defaults,
            isFixture: fixture != nil
        )
        // Join on the full-screen alert finishes the meeting's notification too.
        alertCoordinator.didAnswer = { [weak notificationCoordinator] response, meeting in
            notificationCoordinator?.fullScreenAnswered(response, meeting: meeting)
        }
        self.alertCoordinator = alertCoordinator
        self.notificationCoordinator = notificationCoordinator
        self.updateChecker = UpdateChecker(preferences: preferences, fixtureScenario: fixture)
        // System Settings › Notifications › Join!'s link back.
        notificationCoordinator.openSettings = { [weak self] in self?.openSettings(pane: .fullScreenAlert) }
    }

    func start() {
        Task { await meetingStore.start() }
        if !isFixture { alertCoordinator.start() }
        // A fixture run reads its stand-in's permission for the status line, and plans nothing.
        notificationCoordinator.start()

        // Ticking on :00 and :30 keeps "in 4 min" in step with meetings, which start on whole minutes.
        let interval: TimeInterval = 30
        let firstTick = Date(timeIntervalSinceReferenceDate: (Date().timeIntervalSinceReferenceDate / interval).rounded(.up) * interval)
        let ticker = Timer(fire: firstTick, interval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.now = Date()
                self.updateChecker.tick(now: self.now)
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
            MainActor.assumeIsolated { self?.updateChecker.tick(now: Date()) }
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
            display: preferences.menuBarDisplay,
            startingSoonWindow: preferences.startingSoonPill.window
        )
    }

    var panelContent: PanelContent {
        PanelPresenter.content(
            meetings: meetingStore.meetings,
            alertable: meetingStore.alertableMeetings,
            dismissed: meetingStore.dismissals,
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

    /// Brings `now` up to the current time, for fresh countdowns; the calendars aren't read again
    /// (that's `MeetingStore.refresh()`).
    func resetClock() {
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

    /// The card's and a row's Dismiss buttons, or the choice made in a repeating event's Dismiss menu: no
    /// alerts for this occurrence (a notification already delivered goes too), and with All Future Events for
    /// its series' later ones too (`DismissedEvents.dismissing`), and the menu bar item and the card move on
    /// to what comes next. The panel stays open and lists them as dismissed until they end. Only a meeting
    /// that may alert can be dismissed; anything else is left alone.
    func dismiss(_ meeting: Meeting, scope: DismissScope = .thisEvent) {
        guard meetingStore.alertableMeetings.contains(where: { $0.id == meeting.id }) else { return }
        updateDismissedEvents(preferences.dismissedEvents.dismissing(meeting, scope: scope))
    }

    /// A dismissed row's Restore, or the choice made in a repeating event's Restore menu: the menu bar item
    /// and the card take the meeting back, with All Future Events its series' later occurrences too, and its
    /// alerts come at once if they're still due (the scheduler's usual late grace and snooze rules).
    func restore(_ meeting: Meeting, scope: DismissScope = .thisEvent) {
        updateDismissedEvents(preferences.dismissedEvents.restoring(meeting, scope: scope))
    }

    /// Both alert coordinators, the menu bar item and the panel all follow `MeetingStore.alertableMeetings`,
    /// which reads the dismissed events, so this one write updates them all.
    private func updateDismissedEvents(_ events: DismissedEvents) {
        let date = Date()
        // Pruned as it's written, so entries for events that are over don't wait for the next calendar read.
        let pruned = events.pruned(at: date, meetings: meetingStore.meetings)
        // Fresh countdowns for whatever takes the card and the menu bar.
        now = date
        guard pruned != preferences.dismissedEvents else { return }
        preferences.dismissedEvents = pruned
    }

    /// The update bar's button: Install, Install and Relaunch once the new copy is downloaded and verified,
    /// Download Page after a failed install, Show in Finder once the new copy waits in a folder.
    func performUpdateAction() {
        guard let update = updateChecker.offeredUpdate else { return }
        switch updateChecker.install {
        case .idle:
            updateChecker.installUpdate()
        case .ready:
            updateChecker.installAndRelaunch()
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
        case .downloading, .verifying, .installing:
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

    /// The status line's Open System Settings: Notifications › Join!, else the Notifications pane.
    func openNotificationSettings() {
        closePanel?()
        let urls = Bundle.main.bundleIdentifier.map { NotificationStatus.settingsURLs(bundleIdentifier: $0) } ?? NotificationStatus.settingsURLs()
        for url in urls where NSWorkspace.shared.open(url) { return }
        // Fixed URLs and the bundle id: nothing personal.
        let tried = urls.map(\.absoluteString).joined(separator: ", ")
        Logger.settings.error("Couldn't open the notification settings; System Settings took none of \(tried, privacy: .public)")
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
