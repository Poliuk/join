import AppKit
import Observation
import JoinCore

struct AlertStateRecord: Codable {
    var state: AlertState
    var expiresAt: Date
}

/// Turns the pure scheduler's answer into timers, windows and sounds.
@MainActor
@Observable
final class AlertCoordinator {
    static let heartbeatInterval: TimeInterval = 30
    static let fireLeeway: TimeInterval = 0.5
    static let appNapGuardWindow: TimeInterval = 5 * 60
    static let statesKey = "alertStates"
    static let pauseKey = "pauseState"

    /// Persisted, so "Pause until tomorrow" survives a relaunch.
    private(set) var pauseState: PauseState = .active
    private(set) var activeMeetings: [Meeting] = []
    private(set) var nextFireAt: Date?

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
        if let data = defaults.data(forKey: Self.statesKey),
           let decoded = try? JSONDecoder().decode([String: AlertStateRecord].self, from: data) {
            states = decoded
        }
        if let data = defaults.data(forKey: Self.pauseKey),
           let decoded = try? JSONDecoder().decode(PauseState.self, from: data) {
            pauseState = decoded.resolved(at: Date())
        }
    }

    func start() {
        started = true
        observeChanges(of: { [store] in _ = store.alertableMeetings }) { [weak self] in
            self?.meetingsDidChange()
        }
        heartbeat = Timer.scheduledTimer(withTimeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.replan() }
        }
        heartbeat?.tolerance = 5
        replan()
    }

    /// Read `pauseState.isPaused(at:)` with a fresh date when rendering; a timed pause ends on its own.
    var isPaused: Bool { pauseState.isPaused(at: Date()) }

    func pause(_ option: PauseOption) {
        setPauseState(option.state(from: Date()))
    }

    func resume() {
        setPauseState(.active)
    }

    private func setPauseState(_ state: PauseState) {
        pauseState = state
        defaults.set(try? JSONEncoder().encode(state), forKey: Self.pauseKey)
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

        // One alert at a time: whatever is due next waits until the current one is closed.
        guard activeMeetings.isEmpty else {
            cancelFireTimer()
            return
        }

        let plan = AlertScheduler.nextPlan(
            meetings: store.alertableMeetings,
            states: states.mapValues(\.state),
            leadTime: preferences.leadTime,
            isPaused: pauseState.isPaused(at: now),
            now: now
        )

        cancelFireTimer()
        nextFireAt = plan?.fireAt
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
        for meeting in plan.meetings {
            states[meeting.id] = AlertStateRecord(state: .showing, expiresAt: meeting.end)
        }
        persistStates()
        activeMeetings = plan.meetings
        nextFireAt = nil

        let session = AlertSession(
            meetings: plan.meetings,
            appearance: preferences.appearance,
            snoozeDurations: preferences.snoozeDurations,
            actions: AlertActions(
                dismiss: { [weak self] in self?.dismiss() },
                snooze: { [weak self] duration in self?.snooze(for: duration) },
                snoozeUntilEvent: { [weak self] in self?.snoozeUntilEvent() },
                join: { [weak self] meeting in self?.join(meeting) }
            )
        )
        windows.present(session: session, screens: preferences.alertScreens)
        playSound()

        if preferences.autoCloseEnabled {
            autoCloseTimer = Timer.scheduledTimer(withTimeInterval: preferences.autoCloseAfter, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in self?.dismiss() }
            }
        }
    }

    // MARK: User actions

    func dismiss() {
        setActive(to: .dismissed)
        closeAlert()
    }

    func snooze(for duration: TimeInterval) {
        setActive(to: .snoozed(until: Date().addingTimeInterval(duration)))
        closeAlert()
    }

    func snoozeUntilEvent() {
        let now = Date()
        for meeting in activeMeetings {
            let state: AlertState = meeting.start > now.addingTimeInterval(1) ? .snoozed(until: meeting.start) : .dismissed
            states[meeting.id] = AlertStateRecord(state: state, expiresAt: meeting.end)
        }
        closeAlert()
    }

    func join(_ meeting: Meeting) {
        if let url = meeting.joinURL {
            NSWorkspace.shared.open(url)
        }
        dismiss()
    }

    func showDemoAlert() {
        // On a whole second, like a real event, so the countdown starts at 3:00 and steps evenly.
        let start = Date(timeIntervalSinceReferenceDate: (Date.timeIntervalSinceReferenceDate + 3 * 60).rounded(.down))
        let demo = Meeting(
            id: "demo",
            title: "Hello, I’m a demo event",
            start: start,
            end: start.addingTimeInterval(60 * 60),
            calendarTitle: "Work",
            calendarColor: RGBA(rgb: 0x1A9FC0),
            location: "Conference Room A",
            joinURL: URL(string: "https://meet.google.com/abc-defg-hij")
        )
        let session = AlertSession(
            meetings: [demo],
            appearance: preferences.appearance,
            snoozeDurations: preferences.snoozeDurations,
            actions: AlertActions(
                dismiss: { [weak self] in self?.closeDemo() },
                snooze: { [weak self] _ in self?.closeDemo() },
                snoozeUntilEvent: { [weak self] in self?.closeDemo() },
                join: { [weak self] _ in self?.closeDemo() }
            ),
            isDemo: true
        )
        windows.present(session: session, screens: preferences.alertScreens)
    }

    private func closeDemo() {
        windows.dismiss()
        if !activeMeetings.isEmpty {
            // A real alert was interrupted by the demo; bring it back.
            let meetings = activeMeetings
            activeMeetings = []
            for meeting in meetings { states[meeting.id] = AlertStateRecord(state: .pending, expiresAt: meeting.end) }
            replan()
        }
    }

    // MARK: Helpers

    private func setActive(to state: AlertState) {
        for meeting in activeMeetings {
            states[meeting.id] = AlertStateRecord(state: state, expiresAt: meeting.end)
        }
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
        defaults.set(try? JSONEncoder().encode(states), forKey: Self.statesKey)
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
