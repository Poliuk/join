import AppKit
import Observation
import OSLog
import JoinCore

/// The second kind of alert: macOS notifications at Notify me's time. Plans with `AlertScheduler`
/// (`NotificationSchedule`) and its own per-meeting states, posts each notification itself when it's due, and
/// handles the user's responses. It isn't held back by the full-screen alert's one-at-a-time rule; it shares
/// that alert's pause (`AlertCoordinator.pauseState`), the panel's dismissals and the Events choices (these two
/// through `MeetingStore.alertableMeetings`), and Join from either kind finishes both. A fixture run never
/// plans or sends anything, and its notification center is a stand-in (`FixtureNotificationCenter`).
@Observable
final class NotificationCoordinator {
    private static let heartbeatInterval: TimeInterval = 30
    private static let fireLeeway: TimeInterval = 0.5
    private static let appNapGuardWindow: TimeInterval = 5 * 60
    private static let statesKey = "notificationStates"

    /// What macOS lets Join!'s notifications do: read at launch, when Join! becomes active, when Settings
    /// becomes key, and after asking.
    private(set) var permission: NotificationPermission = .notDetermined

    /// The status line, the Notification box's last row, if any.
    var status: NotificationStatus? {
        NotificationStatus.current(
            notificationsEnabled: preferences.notificationsEnabled,
            playsSound: preferences.notificationPlaysSound,
            permission: permission
        )
    }

    /// Whether Test Notification works, and its help tag.
    var testNotificationButton: TestNotificationButton {
        TestNotificationButton(permission: permission, isFixture: isFixture)
    }

    /// Opens Settings on the Alerts pane: System Settings › Notifications › Join!'s link back.
    @ObservationIgnored var openSettings: (() -> Void)?

    @ObservationIgnored private let center: any NotificationCenterClient
    @ObservationIgnored private let store: MeetingStore
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let alerts: AlertCoordinator
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isFixture: Bool
    @ObservationIgnored private var states: [String: AlertStateRecord] = [:]
    @ObservationIgnored private var responder: NotificationResponder?
    @ObservationIgnored private var fireTimer: DispatchSourceTimer?
    @ObservationIgnored private var heartbeat: Timer?
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var activationObservers: [NSObjectProtocol] = []
    /// When Join! asked macOS, until it answers. For up to `NotificationSchedule.askingHold` nothing is sent, so
    /// a notification due at once when Notify me gets a time comes once the user allows it rather than failing
    /// before; after that, the heartbeat sends what's due whatever the answer.
    @ObservationIgnored private var askedAt: Date?
    /// Notify me as `notifyMeDidChange` last saw it. While Notify me has a time this hasn't seen, its first ask
    /// hasn't started, so nothing is sent either (`NotificationSchedule.holdsSending`): a preset picked from Never
    /// writes the time before Notify me, so the re-plan for the time runs before the ask, and the heartbeat or the
    /// fire timer may too. `askIfNeeded` sets `askedAt` as this is set, so the hold passes from one to the other.
    @ObservationIgnored private var handledEnabled = false
    /// Nothing is planned until `start()`, so a coordinator that is never started never sends anything.
    @ObservationIgnored private var started = false

    init(
        center: any NotificationCenterClient,
        store: MeetingStore,
        preferences: Preferences,
        alerts: AlertCoordinator,
        defaults: UserDefaults = .standard,
        isFixture: Bool
    ) {
        self.center = center
        self.store = store
        self.preferences = preferences
        self.alerts = alerts
        self.defaults = defaults
        self.isFixture = isFixture
        // What can't be read is logged and left out: every meeting is then still to be notified, unless the
        // late grace has passed.
        states = defaults.decodedJSON(
            [String: AlertStateRecord].self, forKey: Self.statesKey, description: "the saved notification states", log: .notifications
        ) ?? [:]
    }

    /// Hands macOS the responder that receives the responses, before launch finishes, so a response that
    /// launched Join! isn't lost. A fixture's stand-in sets nothing.
    func startResponding() {
        guard responder == nil else { return }
        let responder = NotificationResponder(
            onReply: { [weak self] reply in self?.handle(reply) },
            onOpenSettings: { [weak self] in self?.openSettings?() }
        )
        self.responder = responder
        center.setResponder(responder)
    }

    /// Reads the permission, follows Notify me so that its first time asks macOS, and re-reads the
    /// permission whenever Join! becomes active or Settings becomes key; in a real run, also plans and sends
    /// notifications. A fixture run calls it too, for the status line, and its stand-in answers.
    func start() {
        refreshPermission()
        observeActivation()
        // Notify me on at launch is already handled: no prompt, and nothing held.
        handledEnabled = preferences.notificationsEnabled
        // Notify me leaving Never asks macOS the first time; going back to Never stops what's planned.
        observeChanges(of: { [preferences] in _ = preferences.notificationsEnabled }) { [weak self] in
            self?.notifyMeDidChange()
        }
        guard !isFixture else { return }

        started = true
        center.registerCategories(snoozeDurations: preferences.snoozeDurations)
        // macOS looks a category's buttons up when it shows a notification, so the new durations reach the
        // ones already delivered too.
        observeChanges(of: { [preferences] in _ = preferences.snoozeDurations }) { [weak self] in
            guard let self else { return }
            center.registerCategories(snoozeDurations: preferences.snoozeDurations)
        }
        observeChanges(of: { [store] in _ = store.alertableMeetings }) { [weak self] in
            self?.meetingsDidChange()
        }
        // Notify me's time, and the pause shared with the full-screen alert. Play sound needs nothing: it's
        // read as each notification is sent. A time picked from Never comes before Notify me itself, so this
        // re-plan sends nothing until the ask has started (`handledEnabled`).
        observeChanges(of: { [preferences, alerts] in
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

    // MARK: Permission

    /// Reads what macOS allows now; there's no change callback. At launch, this is when notifications left
    /// over from an earlier run for meetings now gone are withdrawn.
    func refreshPermission() {
        Task {
            permission = await center.permission()
            withdrawStale()
        }
    }

    private func notifyMeDidChange() {
        handledEnabled = preferences.notificationsEnabled
        guard preferences.notificationsEnabled else {
            replan()
            return
        }
        askIfNeeded { [weak self] _ in self?.replan() }
    }

    /// Asks macOS when nothing is decided yet (`NotificationPermission.needsAsking`), on a fresh read since
    /// the user may have answered in System Settings meanwhile; then runs `then` with the answer in
    /// `permission`. Join! never asks at launch, so an upgrade never prompts.
    private func askIfNeeded(then: @escaping (NotificationPermission) -> Void) {
        askedAt = Date()
        cancelFireTimer()
        Task {
            var current = await center.permission()
            if current.needsAsking {
                current = await center.requestPermission()
                Logger.notifications.notice("Asked macOS to send notifications: \(String(describing: current), privacy: .public)")
            }
            permission = current
            askedAt = nil
            then(current)
        }
    }

    /// Follows Join! becoming active and Settings becoming key, as Open at login does, so the status line
    /// clears once the user fixes the setting in System Settings.
    private func observeActivation() {
        guard activationObservers.isEmpty else { return }
        let center = NotificationCenter.default
        activationObservers = [
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshPermission() }
            },
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] notification in
                let window = notification.object as? NSWindow
                MainActor.assumeIsolated {
                    guard window?.identifier == .settingsWindow else { return }
                    self?.refreshPermission()
                }
            },
        ]
    }

    // MARK: Planning

    func replan() {
        guard started else { return }
        let now = Date()
        pruneStates(now: now)
        cancelFireTimer()
        // Waiting for the ask (`handledEnabled`, `askedAt`): it re-plans once macOS answers.
        guard !NotificationSchedule.holdsSending(
            notificationsEnabled: preferences.notificationsEnabled,
            handledEnabled: handledEnabled,
            askedAt: askedAt,
            now: now
        ) else { return }

        // Whatever is due now goes out at once, each meeting with its own notification; there's no
        // one-at-a-time rule, so the loop ends once nothing more is due.
        var plan = nextPlan(now: now)
        while let due = plan, due.fireAt.timeIntervalSince(now) <= Self.fireLeeway {
            send(due.meetings, now: now)
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

    /// Each meeting is sent once (`NotificationSchedule.sentState`), and silently while its full-screen alert
    /// is on screen. A full-screen alert due at this same moment goes up first, so the two sounds never
    /// overlap.
    private func send(_ meetings: [Meeting], now: Date) {
        alerts.replan()
        let contents = meetings.map { meeting in
            states[meeting.id] = AlertStateRecord(state: NotificationSchedule.sentState, expiresAt: meeting.end)
            let playsSound = NotificationSchedule.playsSound(
                preference: preferences.notificationPlaysSound,
                fullScreenAlertShowing: alerts.isAlerting(about: meeting.id)
            )
            return NotificationContent.meeting(meeting, playsSound: playsSound, now: now)
        }
        persistStates()
        post(contents)
    }

    private func post(_ contents: [NotificationContent]) {
        Task {
            for content in contents {
                do {
                    try await center.post(content)
                } catch {
                    // UNErrorDomain and a code (1 while notifications aren't allowed): nothing personal.
                    Logger.notifications.error("Couldn't send a notification: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    /// The alertable meetings changed: a calendar edit, an Events choice, or an event dismissed or restored
    /// in the panel. What's planned follows, and a delivered notification whose meeting left goes.
    private func meetingsDidChange() {
        replan()
        withdrawStale()
    }

    /// Withdraws the delivered notifications whose meeting is no longer alertable (dismissed from the panel,
    /// cancelled, moved, now Show in the list only or excluded) or has ended. Only once the calendar has been
    /// read, or every meeting would look gone, but whatever the permission read last says: a grant made in
    /// System Settings isn't seen until Join! is next active, yet notifications are delivered meanwhile, and
    /// with nothing delivered there's nothing to withdraw.
    private func withdrawStale() {
        guard started, store.lastRefreshed != nil else { return }
        Task {
            let delivered = await center.deliveredIdentifiers()
            // Read after the wait, so a meeting restored meanwhile keeps its notification.
            let stale = NotificationSchedule.withdrawals(delivered: delivered, alertable: store.alertableMeetings, now: Date())
            guard !stale.isEmpty else { return }
            center.withdraw(stale)
        }
    }

    // MARK: Responses

    /// A full-screen alert was answered for `meeting`. Only Join changes the notification
    /// (`AlertResponse.state`): it won't come, and one already delivered goes.
    func fullScreenAnswered(_ response: AlertResponse, meeting: Meeting) {
        guard let state = response.state(of: .notification, answering: .fullScreen, meeting: meeting, now: Date()) else { return }
        states[meeting.id] = AlertStateRecord(state: state, expiresAt: meeting.end)
        persistStates()
        center.withdraw([NotificationIdentifier.meeting(meeting.id).rawValue])
        replan()
    }

    /// A response to one of Join!'s notifications. A click on the notification itself does nothing. Join opens the
    /// link and finishes both kinds; Snooze and At event start bring this notification back, leaving the
    /// full-screen alert alone. On the test notification, Join opens the demo event's link too, so the test tries
    /// it end to end (the user's ask, 2026-10-19), and every other action only closes it.
    private func handle(_ reply: NotificationReply) {
        guard let identifier = reply.identifier, let response = reply.response else { return }
        guard case .meeting(let id) = identifier, let payload = reply.payload, payload.meetingID == id else {
            if identifier == .demo {
                if response == .join, let url = reply.payload?.joinURL { NSWorkspace.shared.open(url) }
                center.withdraw([identifier.rawValue])
            }
            return
        }
        // From what the notification carries: the calendar may not be read yet when a response launches Join!.
        let meeting = Meeting(id: id, title: "", start: payload.start, end: payload.end, joinURL: payload.joinURL)
        if response == .join, let url = payload.joinURL {
            NSWorkspace.shared.open(url)
        }
        if let state = response.state(of: .notification, answering: .notification, meeting: meeting, now: Date()) {
            states[id] = AlertStateRecord(state: state, expiresAt: meeting.end)
            persistStates()
        }
        // A snooze sends it again under the same identifier; until then it's off the screen.
        center.withdraw([identifier.rawValue])
        alerts.notificationAnswered(response, meeting: meeting)
        replan()
    }

    /// macOS may send a reopen event along with a click on a notification, and a reopen opens Settings. Clicking
    /// a notification does nothing, so a reopen this soon after a response is ignored.
    var ignoresReopen: Bool {
        NotificationSchedule.ignoresReopen(lastResponse: responder?.lastResponse, now: Date())
    }

    // MARK: Test Notification

    /// Test Notification: sends the demo event's notification at once, while alerts are paused and while Notify
    /// me is Never too, as Test Full-Screen Alert works. The first click asks macOS when nothing is decided yet;
    /// nothing is sent while notifications are denied. It follows Play sound and the snooze durations.
    func sendDemoNotification() {
        askIfNeeded { [weak self] permission in
            guard let self else { return }
            // A due notification waited for the answer.
            replan()
            guard permission != .denied else { return }
            post([NotificationContent.demo(playsSound: preferences.notificationPlaysSound, now: Date())])
        }
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
