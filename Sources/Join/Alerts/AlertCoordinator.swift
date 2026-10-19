import AppKit
import Observation
import OSLog
import JoinCore

/// Turns the pure scheduler's answer into timers, windows and sounds, for the full-screen alert. The
/// notification, the other kind, has its own coordinator (`NotificationCoordinator`), which reads the pause
/// kept here.
@Observable
final class AlertCoordinator {
    private static let heartbeatInterval: TimeInterval = 30
    private static let fireLeeway: TimeInterval = 0.5
    private static let appNapGuardWindow: TimeInterval = 5 * 60
    private static let statesKey = "alertStates"
    private static let pauseKey = "pauseState"

    /// Persisted, so "Pause until tomorrow" survives a relaunch. It pauses both kinds of alert.
    private(set) var pauseState: PauseState = .active
    private(set) var activeMeetings: [Meeting] = []

    /// Called right before any alert, real or demo, goes on screen.
    @ObservationIgnored var willPresentAlert: (() -> Void)?
    /// Called for each meeting of a real alert once it's answered or closes automatically, with what that
    /// meant for it: Join for the meeting joined and close for the others in the alert, a snooze or At event
    /// start for all of them. The notification follows it (`AlertResponse.state`).
    @ObservationIgnored var didAnswer: ((AlertResponse, Meeting) -> Void)?

    @ObservationIgnored private let store: MeetingStore
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let windows: AlertWindowController
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var states: [String: AlertStateRecord] = [:]
    @ObservationIgnored private var fireTimer: DispatchSourceTimer?
    @ObservationIgnored private var heartbeat: Timer?
    @ObservationIgnored private var autoCloseTimer: Timer?
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var sound: NSSound?
    /// Nothing is scheduled until `start()`, so a coordinator that is never started never alerts.
    @ObservationIgnored private var started = false

    init(store: MeetingStore, preferences: Preferences, windows: AlertWindowController, defaults: UserDefaults = .standard) {
        self.store = store
        self.preferences = preferences
        self.windows = windows
        self.defaults = defaults
        // What can't be read is logged and left out: no snoozes or dismissals, no pause.
        states = defaults.decodedJSON(
            [String: AlertStateRecord].self, forKey: Self.statesKey, description: "the saved snoozes and dismissals", log: .alerts
        ) ?? [:]
        if let saved = defaults.decodedJSON(PauseState.self, forKey: Self.pauseKey, description: "the saved pause", log: .alerts) {
            pauseState = saved.resolved(at: Date())
        }
    }

    func start() {
        started = true
        observeChanges(of: { [store] in _ = store.alertableMeetings }) { [weak self] in
            self?.meetingsDidChange()
        }
        heartbeat = Timer.scheduledTimer(withTimeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.replan() }
        }
        heartbeat?.tolerance = 5
        replan()
    }

    func pause(_ option: PauseOption) {
        setPauseState(option.state(from: Date()))
    }

    func resume() {
        setPauseState(.active)
    }

    private func setPauseState(_ state: PauseState) {
        pauseState = state
        defaults.setJSON(state, forKey: Self.pauseKey, log: .alerts)
        replan()
    }

    // MARK: Planning

    func replan() {
        guard started else { return }
        let now = Date()
        pruneStates(now: now)
        if pauseState.resolved(at: now) != pauseState {
            pauseState = .active
            defaults.removeObject(forKey: Self.pauseKey)
        }

        // One alert at a time: whatever is due next waits until the current one is closed. Switching
        // to Never while one is up leaves it there.
        guard activeMeetings.isEmpty else {
            cancelFireTimer()
            return
        }

        // Alert me set to Never plans nothing, like a pause: snoozed alerts wait too. The menu bar and
        // the panel don't read it, so they carry on.
        let plan = AlertScheduler.nextPlan(
            meetings: store.alertableMeetings,
            states: states.mapValues(\.state),
            leadTime: preferences.leadTime,
            isPaused: pauseState.isPaused(at: now) || !preferences.fullScreenAlertsEnabled,
            now: now
        )

        cancelFireTimer()
        guard let plan else {
            endActivity()
            return
        }

        let delay = plan.fireAt.timeIntervalSince(now)
        if delay <= Self.fireLeeway {
            fire(plan)
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(wallDeadline: .now() + delay, leeway: .milliseconds(Int(Self.fireLeeway * 1000)))
        timer.setEventHandler { [weak self] in self?.replan() }
        timer.resume()
        fireTimer = timer

        if delay < Self.appNapGuardWindow { beginActivity() } else { endActivity() }
    }

    /// The alertable meetings changed: a calendar edit, an Events choice, or an event dismissed from the
    /// panel. An alert on screen drops the meetings that are gone, closing once none is left, and the
    /// replan cancels a pending alert for them.
    private func meetingsDidChange() {
        if !activeMeetings.isEmpty {
            let known = Set(store.alertableMeetings.map(\.id))
            let remaining = activeMeetings.filter { known.contains($0.id) }
            if remaining.isEmpty {
                closeAlert()
                return
            }
            if remaining.count != activeMeetings.count {
                activeMeetings = remaining
                windows.update(meetings: remaining)
            }
        }
        replan()
    }

    private func fire(_ plan: AlertPlan) {
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
        for meeting in plan.meetings {
            states[meeting.id] = AlertStateRecord(state: .showing, expiresAt: meeting.end)
        }
        persistStates()
        activeMeetings = plan.meetings

        let session = AlertSession(
            meetings: plan.meetings,
            appearance: preferences.appearance,
            snoozeDurations: preferences.snoozeDurations.all,
            actions: AlertActions(
                dismiss: { [weak self] in self?.dismiss() },
                snooze: { [weak self] duration in self?.snooze(for: duration) },
                snoozeUntilEvent: { [weak self] in self?.snoozeUntilEvent() },
                join: { [weak self] meeting in self?.join(meeting) }
            )
        )
        willPresentAlert?()
        windows.present(session: session, screens: preferences.alertScreens)
        playSound()

        if preferences.autoCloseEnabled {
            // Synchronously: a dismissal left for later could close the next alert, which `closeAlert` may
            // put up straight away, instead of this one.
            autoCloseTimer = Timer.scheduledTimer(withTimeInterval: preferences.autoCloseAfter, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            }
        }
    }

    // MARK: User actions

    func dismiss() {
        answer(.close)
    }

    func snooze(for duration: TimeInterval) {
        answer(.snooze(duration))
    }

    func snoozeUntilEvent() {
        answer(.snoozeUntilStart)
    }

    /// Join finishes this meeting's notification too, and the alert closes for the others it shows.
    func join(_ meeting: Meeting) {
        if let url = meeting.joinURL {
            NSWorkspace.shared.open(url)
        }
        answer(.join, joined: meeting.id)
    }

    /// A real alert is on screen. The demo never replaces it.
    var isAlerting: Bool { !activeMeetings.isEmpty }

    /// A real alert for this meeting is on screen.
    func isAlerting(about meetingID: Meeting.ID) -> Bool {
        activeMeetings.contains { $0.id == meetingID }
    }

    /// The user answered `meeting`'s notification. Only Join changes the full-screen alert (`AlertResponse.state`):
    /// it won't come, and one on screen drops the meeting, closing once none is left. Snooze and At event
    /// start leave it alone, so a notification before and a full-screen alert at the start both come.
    func notificationAnswered(_ response: AlertResponse, meeting: Meeting) {
        guard let state = response.state(of: .fullScreen, answering: .notification, meeting: meeting, now: Date()) else { return }
        states[meeting.id] = AlertStateRecord(state: state, expiresAt: meeting.end)
        guard isAlerting(about: meeting.id) else {
            persistStates()
            replan()
            return
        }
        let remaining = activeMeetings.filter { $0.id != meeting.id }
        guard !remaining.isEmpty else {
            closeAlert()
            return
        }
        activeMeetings = remaining
        windows.update(meetings: remaining)
        persistStates()
    }

    /// Test Full-Screen Alert, on Alerts and Appearance, and the `showDemoAlert` script hook: the demo event's
    /// full-screen alert, on the chosen screens in the current look. Join opens the demo event's link, as a real
    /// alert's does, so the test tries it end to end (the user's ask, 2026-10-19); every button closes it.
    func showDemoAlert() {
        guard !isAlerting else { return }
        let demo = DemoEvent.meeting(now: Date())
        let session = AlertSession(
            meetings: [demo],
            appearance: preferences.appearance,
            snoozeDurations: preferences.snoozeDurations.all,
            actions: AlertActions(
                dismiss: { [weak self] in self?.closeDemo() },
                snooze: { [weak self] _ in self?.closeDemo() },
                snoozeUntilEvent: { [weak self] in self?.closeDemo() },
                join: { [weak self] _ in
                    if let url = DemoEvent.joinURL { NSWorkspace.shared.open(url) }
                    self?.closeDemo()
                }
            ),
            isDemo: true
        )
        willPresentAlert?()
        windows.present(session: session, screens: preferences.alertScreens)
    }

    private func closeDemo() {
        // A real alert that fires during the demo replaces it, and must stay up.
        guard !isAlerting else { return }
        windows.dismiss()
    }

    // MARK: Helpers

    /// Sets each meeting on screen to its state after `response` (`AlertResponse.state`): the meeting
    /// `joined` is Join's, and the others close. Then the alert closes.
    private func answer(_ response: AlertResponse, joined: Meeting.ID? = nil) {
        let now = Date()
        for meeting in activeMeetings {
            let own: AlertResponse = joined == nil || meeting.id == joined ? response : .close
            if let state = own.state(of: .fullScreen, answering: .fullScreen, meeting: meeting, now: now) {
                states[meeting.id] = AlertStateRecord(state: state, expiresAt: meeting.end)
            }
            didAnswer?(own, meeting)
        }
        closeAlert()
    }

    private func closeAlert() {
        windows.dismiss()
        stopSound()
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
        activeMeetings = []
        persistStates()
        replan()
    }

    private func pruneStates(now: Date) {
        let before = states.count
        states = states.filter { $0.value.expiresAt > now }
        if states.count != before { persistStates() }
    }

    private func persistStates() {
        defaults.setJSON(states, forKey: Self.statesKey, log: .alerts)
    }

    private func cancelFireTimer() {
        fireTimer?.cancel()
        fireTimer = nil
    }

    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "A meeting alert is due shortly"
        )
    }

    private func endActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    private func playSound() {
        guard let sound = SystemSounds.sound(named: preferences.soundName) else { return }
        sound.loops = preferences.soundRepeats
        sound.play()
        self.sound = sound
    }

    private func stopSound() {
        sound?.stop()
        sound = nil
    }
}
