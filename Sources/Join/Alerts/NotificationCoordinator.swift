import AppKit
import Observation
import OSLog
import JoinCore

/// The second kind of alert: Join!'s notification cards at Notify me's time. Plans with `AlertScheduler`
/// (`NotificationSchedule`) and its own per-meeting states, shows each card through `NotificationCardController`
/// when it's due, closes it automatically after Close automatically's time, and handles the user's answers. It
/// isn't held back by the full-screen alert's one-at-a-time rule; it shares that alert's pause
/// (`AlertCoordinator.pauseState`), the panel's dismissals and the Events choices (these two through
/// `MeetingStore.alertableMeetings`), and Join from either kind or the menu bar panel finishes both. A pause or
/// Never closes the cards on screen. A card on screen at quit comes back, silently, at the next launch while its
/// time lasts; one still waiting for a slot is due again. Fixture runs show cards too: they touch nothing outside
/// the app.
@Observable
final class NotificationCoordinator {
    private static let heartbeatInterval: TimeInterval = 30
    private static let fireLeeway: TimeInterval = 0.5
    private static let appNapGuardWindow: TimeInterval = 5 * 60
    private static let statesKey = "notificationStates"

    /// A card on screen or waiting for a slot, and when it closes by itself.
    private struct AutoClose {
        let card: NotificationCard
        /// When it first came on screen: Close automatically counts from here. Nil while it waits for a slot.
        var appearedAt: Date?
        /// Nil while it waits for a slot, and while Close automatically is Never.
        var timer: Timer?
    }

    @ObservationIgnored private let cards: NotificationCardController
    @ObservationIgnored private let store: MeetingStore
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let alerts: AlertCoordinator
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var states: [String: AlertStateRecord] = [:]
    @ObservationIgnored private var autoCloses: [Meeting.ID: AutoClose] = [:]
    @ObservationIgnored private var fireTimer: DispatchSourceTimer?
    @ObservationIgnored private var heartbeat: Timer?
    @ObservationIgnored private var activity: NSObjectProtocol?
    /// Nothing is planned until `start()`, so a coordinator that is never started never shows anything.
    @ObservationIgnored private var started = false
    /// Whether the cards on screen at the last quit have had their chance to come back: once, after the first
    /// calendar read.
    @ObservationIgnored private var restoredCards = false

    init(
        cards: NotificationCardController,
        store: MeetingStore,
        preferences: Preferences,
        alerts: AlertCoordinator,
        defaults: UserDefaults = .standard
    ) {
        self.cards = cards
        self.store = store
        self.preferences = preferences
        self.alerts = alerts
        self.defaults = defaults
        // What can't be read is logged and left out: every meeting is then still to get a card, unless the
        // late grace has passed.
        states = defaults.decodedJSON(
            [String: AlertStateRecord].self, forKey: Self.statesKey, description: "the saved notification states", log: .notifications
        ) ?? [:]
        cards.screens = preferences.notificationScreens
        // Worked out as the menu opens: the snooze times and Alert me as they are then.
        cards.makeMenu = { [preferences] card in
            NotificationMenu(
                for: card,
                snoozeDurations: preferences.snoozeDurations,
                fullScreenAlertsEnabled: preferences.fullScreenAlertsEnabled,
                now: Date()
            )
        }
        cards.onAnswer = { [weak self] response, card in
            self?.answer(response, card: card)
        }
        cards.onAppear = { [weak self] card in
            self?.cardDidAppear(card)
        }
        cards.isFullScreenAlertShowing = { [alerts] meetingID in
            alerts.isAlerting(about: meetingID)
        }
    }

    /// Plans the cards, following the meetings, Notify me, its time and the pause shared with the full-screen
    /// alert, and keeps the cards on screen in step with Show on and Close automatically.
    func start() {
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
            self?.closeCardsIfStopped()
            self?.replan()
        }
        observeChanges(of: { [preferences] in _ = preferences.notificationScreens }) { [weak self] in
            guard let self else { return }
            cards.screens = preferences.notificationScreens
        }
        observeChanges(of: { [preferences] in
            _ = preferences.notificationAutoCloseEnabled
            _ = preferences.notificationAutoCloseAfter
        }) { [weak self] in
            self?.autoCloseDidChange()
        }
        // Also catches what no change announces: a meeting that ends, a timer late after sleep, a card whose
        // Close automatically time passed while the Mac slept.
        heartbeat = Timer.scheduledTimer(withTimeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.meetingsDidChange() }
        }
        heartbeat?.tolerance = 5
        meetingsDidChange()
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

    /// Each meeting's card shows once (`NotificationSchedule.shownState`), with the alert sound, as it comes on
    /// screen, unless its full-screen alert is up then (`NotificationCardController.isFullScreenAlertShowing`). A
    /// full-screen alert due at this same moment goes up first, so the two sounds never overlap.
    private func show(_ meetings: [Meeting]) {
        alerts.replan()
        for meeting in meetings {
            // When it appeared is written as it comes on screen (`cardDidAppear`): it may wait for a slot first.
            states[meeting.id] = AlertStateRecord(state: NotificationSchedule.shownState, expiresAt: meeting.end)
            present(NotificationCard.meeting(meeting), playsSound: preferences.notificationPlaysSound)
        }
        persistStates()
    }

    /// Hands `card` over to the controller. Its Close automatically starts once it's on screen
    /// (`cardDidAppear`), which may be at once, inside `cards.show`, or once a slot frees.
    private func present(_ card: NotificationCard, playsSound: Bool) {
        autoCloses[card.id]?.timer?.invalidate()
        autoCloses[card.id] = AutoClose(card: card)
        cards.show(card, playsSound: playsSound)
    }

    /// `card` came on screen for the first time: Close automatically counts from now, or, for a card brought
    /// back after a relaunch, from when it first appeared before the quit, which its meeting's state keeps.
    private func cardDidAppear(_ card: NotificationCard) {
        guard autoCloses[card.id]?.card == card else { return }
        var appearedAt = Date()
        if !card.isTest, let record = states[card.id], record.state == NotificationSchedule.shownState {
            if let restored = record.appearedAt {
                appearedAt = restored
            } else {
                states[card.id] = AlertStateRecord(state: record.state, expiresAt: record.expiresAt, appearedAt: appearedAt)
                persistStates()
            }
        }
        autoCloses[card.id]?.appearedAt = appearedAt
        autoCloses[card.id]?.timer = autoCloseTimer(for: card, appearedAt: appearedAt)
    }

    /// The alertable meetings changed: a calendar edit, an Events choice, or an event dismissed or restored
    /// in the panel. What's planned follows, and a card whose meeting left goes.
    private func meetingsDidChange() {
        restoreCardsAfterLaunch()
        closeOverdue(now: Date())
        replan()
        withdrawStale()
    }

    /// The cards on screen when Join! last quit (or installed an update) come back, without a sound, once the
    /// calendar has been read: those whose meeting is still alertable and hasn't ended, and whose Close
    /// automatically time hasn't come (`NotificationSchedule.reshowsAfterRelaunch`). While cards are stopped
    /// (paused, Never) they're due again instead, as a pause leaves them, and so is a card that was still waiting
    /// for a slot, which never appeared: the usual plan brings it, with its sound.
    private func restoreCardsAfterLaunch() {
        guard started, !restoredCards, store.lastRefreshed != nil else { return }
        restoredCards = true
        let now = Date()
        let stopped = NotificationSchedule.isStopped(isEnabled: preferences.notificationsEnabled, pauseState: alerts.pauseState, now: now)
        for meeting in store.alertableMeetings {
            guard let record = states[meeting.id], record.state == NotificationSchedule.shownState else { continue }
            guard !stopped, let appearedAt = record.appearedAt else {
                states[meeting.id] = AlertStateRecord(state: NotificationSchedule.hiddenState, expiresAt: record.expiresAt)
                continue
            }
            let reshows = NotificationSchedule.reshowsAfterRelaunch(
                meeting: meeting,
                appearedAt: appearedAt,
                autoCloseEnabled: preferences.notificationAutoCloseEnabled,
                autoCloseAfter: preferences.notificationAutoCloseAfter,
                now: now
            )
            if reshows {
                present(NotificationCard.meeting(meeting), playsSound: false)
            }
        }
        persistStates()
    }

    /// Withdraws the cards whose meeting is no longer alertable (dismissed from the panel, cancelled, moved, now
    /// Show in the list only or excluded) or has ended. Only once the calendar has been read, or every meeting
    /// would look gone. Their meetings become dismissed, which plans them no more, as on screen, and keeps a
    /// relaunch from bringing the card back once the meeting is alertable again (Restore in the panel).
    private func withdrawStale() {
        guard started, store.lastRefreshed != nil else { return }
        let withdrawn = NotificationSchedule.withdrawals(shown: cards.shownMeetingIDs, alertable: store.alertableMeetings, now: Date())
        guard !withdrawn.isEmpty else { return }
        for id in withdrawn {
            guard let record = states[id] else { continue }
            states[id] = AlertStateRecord(state: .dismissed, expiresAt: record.expiresAt)
        }
        persistStates()
        closeCards(withdrawn)
    }

    /// Pause alerts, or Notify me set to Never: the meetings' cards on screen close, unanswered, so they're due
    /// again (`NotificationSchedule.hiddenState`) and the usual plan brings them back once alerts resume or Notify
    /// me has a time. Test Notification's card stays.
    private func closeCardsIfStopped() {
        guard started else { return }
        let stopped = NotificationSchedule.isStopped(isEnabled: preferences.notificationsEnabled, pauseState: alerts.pauseState, now: Date())
        let shown = cards.shownMeetingIDs.filter { $0 != DemoEvent.id }
        guard stopped, !shown.isEmpty else { return }
        for id in shown {
            guard let record = states[id] else { continue }
            states[id] = AlertStateRecord(state: NotificationSchedule.hiddenState, expiresAt: record.expiresAt)
        }
        persistStates()
        closeCards(shown)
    }

    private func closeCards(_ meetingIDs: [Meeting.ID]) {
        guard !meetingIDs.isEmpty else { return }
        for id in meetingIDs {
            autoCloses.removeValue(forKey: id)?.timer?.invalidate()
        }
        cards.close(meetingIDs)
    }

    // MARK: Close automatically

    /// Close automatically's time after `appearedAt`, or nil with Never.
    private func autoCloseTime(appearedAt: Date) -> Date? {
        NotificationSchedule.autoCloseTime(
            appearedAt: appearedAt,
            isEnabled: preferences.notificationAutoCloseEnabled,
            after: preferences.notificationAutoCloseAfter
        )
    }

    /// A timer at Close automatically's time after `appearedAt`, or nil with Never. It doesn't count while the
    /// Mac sleeps: the heartbeat closes what it missed (`closeOverdue`).
    private func autoCloseTimer(for card: NotificationCard, appearedAt: Date) -> Timer? {
        guard let closesAt = autoCloseTime(appearedAt: appearedAt) else { return nil }
        let timer = Timer(fire: closesAt, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeAutomatically(card) }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    /// Close automatically changed: each card on screen closes at the new time after it appeared, at once if that
    /// has passed, or stays with Never. Cards waiting for a slot start counting once they're on screen.
    private func autoCloseDidChange() {
        for (id, autoClose) in autoCloses {
            guard let appearedAt = autoClose.appearedAt else { continue }
            autoClose.timer?.invalidate()
            autoCloses[id]?.timer = autoCloseTimer(for: autoClose.card, appearedAt: appearedAt)
        }
    }

    /// Closes the cards whose Close automatically time has passed: their timers stood still while the Mac slept.
    private func closeOverdue(now: Date) {
        for autoClose in autoCloses.values {
            guard let appearedAt = autoClose.appearedAt, let closesAt = autoCloseTime(appearedAt: appearedAt), closesAt <= now else { continue }
            closeAutomatically(autoClose.card)
        }
    }

    /// A card's time is up: as Dismiss, it goes for good (`AlertResponse.close`) and the full-screen alert still
    /// comes. Under the pointer it waits until the pointer leaves.
    private func closeAutomatically(_ card: NotificationCard) {
        guard let autoClose = autoCloses[card.id], autoClose.card == card else { return }
        if !card.isTest, let state = AlertResponse.close.state(of: .notification, answering: .notification, meeting: card.meeting, now: Date()) {
            states[card.id] = AlertStateRecord(state: state, expiresAt: card.meeting.end)
            persistStates()
        }
        closeCards([card.id])
    }

    // MARK: Responses

    /// A full-screen alert was answered for `meeting`. Only Join changes the notification
    /// (`AlertResponse.state`): its card won't come, and one already up goes. Dismissing or snoozing the
    /// full-screen alert leaves the card alone (the user's choice, 2026-10-19).
    func fullScreenAnswered(_ response: AlertResponse, meeting: Meeting) {
        guard let state = response.state(of: .notification, answering: .fullScreen, meeting: meeting, now: Date()) else { return }
        finish(meeting, state: state)
    }

    /// `meeting` was joined from the menu bar panel: as Join on either kind (`AlertResponse.join`), its card
    /// won't come, and one already up goes.
    func joinedFromPanel(_ meeting: Meeting) {
        finish(meeting, state: .dismissed)
    }

    private func finish(_ meeting: Meeting, state: AlertState) {
        states[meeting.id] = AlertStateRecord(state: state, expiresAt: meeting.end)
        persistStates()
        closeCards([meeting.id])
        replan()
    }

    /// An answer on `card`, which has already gone from the screen. Join opens the link and finishes both kinds;
    /// a snooze or At event start brings the card back, and Dismiss closes it for good, leaving the full-screen
    /// alert alone. On the test card, Join opens the demo event's link too, so the test tries it end to end, and
    /// every other choice only closes it.
    private func answer(_ response: AlertResponse, card: NotificationCard) {
        autoCloses.removeValue(forKey: card.id)?.timer?.invalidate()
        if response == .join, let url = card.joinURL {
            NSWorkspace.shared.open(url)
        }
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

    /// Test Notification, and the `showTestNotification` script hook: shows the demo event's card at once,
    /// replacing one already up, while alerts are paused, while Notify me is Never and in a fixture run too, as
    /// Test Full-Screen Alert works. It follows Show on, Play sound, Close automatically and the snooze times,
    /// and changes no real meeting's state.
    func showTestNotification() {
        present(NotificationCard.test(now: Date()), playsSound: preferences.notificationPlaysSound)
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
