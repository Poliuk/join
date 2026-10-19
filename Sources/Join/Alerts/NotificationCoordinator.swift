import AppKit
import Observation
import OSLog
import JoinCore

/// The second kind of alert: Join!'s notification cards at Notify me's time. Plans with `AlertScheduler`
/// (`NotificationSchedule`) and its own per-meeting states, shows each card through its presenter when it's
/// due, and handles the user's answers. It isn't held back by the full-screen alert's one-at-a-time rule; it
/// shares that alert's pause (`AlertCoordinator.pauseState`), the panel's dismissals and the Events choices
/// (these two through `MeetingStore.alertableMeetings`), and Join from either kind finishes both. A fixture run
/// never plans anything.
@Observable
final class NotificationCoordinator {
    private static let heartbeatInterval: TimeInterval = 30
    private static let fireLeeway: TimeInterval = 0.5
    private static let appNapGuardWindow: TimeInterval = 5 * 60
    private static let statesKey = "notificationStates"

    @ObservationIgnored private let presenter: any NotificationPresenter
    @ObservationIgnored private let store: MeetingStore
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let alerts: AlertCoordinator
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isFixture: Bool
    @ObservationIgnored private var states: [String: AlertStateRecord] = [:]
    @ObservationIgnored private var fireTimer: DispatchSourceTimer?
    @ObservationIgnored private var heartbeat: Timer?
    @ObservationIgnored private var activity: NSObjectProtocol?
    /// Nothing is planned until `start()`, so a coordinator that is never started never shows anything.
    @ObservationIgnored private var started = false

    init(
        presenter: any NotificationPresenter,
        store: MeetingStore,
        preferences: Preferences,
        alerts: AlertCoordinator,
        defaults: UserDefaults = .standard,
        isFixture: Bool
    ) {
        self.presenter = presenter
        self.store = store
        self.preferences = preferences
        self.alerts = alerts
        self.defaults = defaults
        self.isFixture = isFixture
        // What can't be read is logged and left out: every meeting is then still to get a card, unless the
        // late grace has passed.
        states = defaults.decodedJSON(
            [String: AlertStateRecord].self, forKey: Self.statesKey, description: "the saved notification states", log: .notifications
        ) ?? [:]
    }

    /// Plans the cards, following the meetings, Notify me, its time and the pause shared with the full-screen
    /// alert. A fixture run plans nothing.
    func start() {
        guard !isFixture else { return }

        started = true
        observeChanges(of: { [store] in _ = store.alertableMeetings }) { [weak self] in
            self?.meetingsDidChange()
        }
        // Play sound needs nothing: it's read as each card is shown.
        observeChanges(of: { [preferences, alerts] in
            _ = preferences.notificationsEnabled
            _ = preferences.notificationLeadTime
            _ = alerts.pauseState
        }) { [weak self] in
            self?.replan()
        }
        heartbeat = Timer.scheduledTimer(withTimeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.replan()
                self?.withdrawStale()
            }
        }
        heartbeat?.tolerance = 5
        replan()
    }

    // MARK: Planning

    func replan() {
        guard started else { return }
        let now = Date()
        pruneStates(now: now)
        cancelFireTimer()

        // Whatever is due now shows at once, each meeting with its own card; there's no one-at-a-time rule, so
        // the loop ends once nothing more is due.
        var plan = nextPlan(now: now)
        while let due = plan, due.fireAt.timeIntervalSince(now) <= Self.fireLeeway {
            show(due.meetings)
            plan = nextPlan(now: now)
        }
        guard let plan else {
            endActivity()
            return
        }

        let delay = plan.fireAt.timeIntervalSince(now)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(wallDeadline: .now() + delay, leeway: .milliseconds(Int(Self.fireLeeway * 1000)))
        timer.setEventHandler { [weak self] in self?.replan() }
        timer.resume()
        fireTimer = timer

        if delay < Self.appNapGuardWindow { beginActivity() } else { endActivity() }
    }

    private func nextPlan(now: Date) -> AlertPlan? {
        NotificationSchedule.nextPlan(
            meetings: store.alertableMeetings,
            states: states.mapValues(\.state),
            leadTime: preferences.notificationLeadTime,
            isEnabled: preferences.notificationsEnabled,
            pauseState: alerts.pauseState,
            now: now
        )
    }

    /// Each meeting's card shows once (`NotificationSchedule.shownState`), and silently while its full-screen
    /// alert is on screen. A full-screen alert due at this same moment goes up first, so the two sounds never
    /// overlap.
    private func show(_ meetings: [Meeting]) {
        alerts.replan()
        for meeting in meetings {
            states[meeting.id] = AlertStateRecord(state: NotificationSchedule.shownState, expiresAt: meeting.end)
            let playsSound = NotificationSchedule.playsSound(
                preference: preferences.notificationPlaysSound,
                fullScreenAlertShowing: alerts.isAlerting(about: meeting.id)
            )
            presenter.show(NotificationCard.meeting(meeting), playsSound: playsSound)
        }
        persistStates()
    }

    /// The alertable meetings changed: a calendar edit, an Events choice, or an event dismissed or restored
    /// in the panel. What's planned follows, and a card whose meeting left goes.
    private func meetingsDidChange() {
        replan()
        withdrawStale()
    }

    /// Withdraws the cards whose meeting is no longer alertable (dismissed from the panel, cancelled, moved, now
    /// Show in the list only or excluded) or has ended. Only once the calendar has been read, or every meeting
    /// would look gone.
    private func withdrawStale() {
        guard started, store.lastRefreshed != nil else { return }
        let stale = NotificationSchedule.withdrawals(shown: presenter.shownMeetingIDs, alertable: store.alertableMeetings, now: Date())
        presenter.close(stale)
    }

    // MARK: Responses

    /// A full-screen alert was answered for `meeting`. Only Join changes the notification
    /// (`AlertResponse.state`): its card won't come, and one already up goes.
    func fullScreenAnswered(_ response: AlertResponse, meeting: Meeting) {
        guard let state = response.state(of: .notification, answering: .fullScreen, meeting: meeting, now: Date()) else { return }
        states[meeting.id] = AlertStateRecord(state: state, expiresAt: meeting.end)
        persistStates()
        presenter.close([meeting.id])
        replan()
    }

    /// An answer on `card`. Join opens the link and finishes both kinds; a snooze or At event start brings the
    /// card back, and Dismiss closes it, leaving the full-screen alert alone. On the test card, Join opens the
    /// demo event's link too, so the test tries it end to end, and every other choice only closes it.
    func answer(_ response: AlertResponse, card: NotificationCard) {
        if response == .join, let url = card.joinURL {
            NSWorkspace.shared.open(url)
        }
        presenter.close([card.id])
        guard !card.isTest else { return }
        let meeting = card.meeting
        if let state = response.state(of: .notification, answering: .notification, meeting: meeting, now: Date()) {
            states[meeting.id] = AlertStateRecord(state: state, expiresAt: meeting.end)
            persistStates()
        }
        alerts.notificationAnswered(response, meeting: meeting)
        replan()
    }

    // MARK: Test Notification

    /// Test Notification: shows the demo event's card at once, replacing one already up, while alerts are
    /// paused and while Notify me is Never too, as Test Full-Screen Alert works. It follows Play sound and the
    /// snooze durations.
    func showTestNotification() {
        presenter.show(NotificationCard.test(now: Date()), playsSound: preferences.notificationPlaysSound)
    }

    // MARK: Helpers

    private func pruneStates(now: Date) {
        let before = states.count
        states = states.filter { $0.value.expiresAt > now }
        if states.count != before { persistStates() }
    }

    private func persistStates() {
        defaults.setJSON(states, forKey: Self.statesKey, log: .notifications)
    }

    private func cancelFireTimer() {
        fireTimer?.cancel()
        fireTimer = nil
    }

    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "A meeting notification is due shortly"
        )
    }

    private func endActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }
}
