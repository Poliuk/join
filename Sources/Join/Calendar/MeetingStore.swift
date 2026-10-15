import AppKit
import Observation
import OSLog
import JoinCore

/// Single source of truth for the meetings the rest of the app sees.
@Observable
final class MeetingStore {
    private static let lookBehind: TimeInterval = 60 * 60
    private static let lookAhead: TimeInterval = 7 * 24 * 60 * 60
    private static let safetyNetInterval: TimeInterval = 15 * 60

    /// The events from the checked calendars that Join! shows: those whose Settings › General › Events
    /// choice is Exclude are left out (`MeetingFilter.visible`).
    private(set) var meetings: [Meeting] = []
    private(set) var calendars: [CalendarInfo] = []
    private(set) var authorization: CalendarAuthorization = .notDetermined
    /// When calendars were last read, for "Updated just now" in Settings.
    private(set) var lastRefreshed: Date?

    @ObservationIgnored private let service: CalendarService
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private var safetyNet: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    init(service: CalendarService, preferences: Preferences) {
        self.service = service
        self.preferences = preferences
    }

    func start() async {
        authorization = service.authorization
        Logger.calendar.notice("Calendar authorization at launch: \(String(describing: self.authorization), privacy: .public)")
        if authorization == .notDetermined {
            do {
                try await service.requestAccess()
            } catch {
                // An EventKit error's domain and code aren't personal.
                Logger.calendar.error("Calendar access request failed: \(String(describing: error), privacy: .public)")
            }
            authorization = service.authorization
            Logger.calendar.notice("Calendar authorization after request: \(String(describing: self.authorization), privacy: .public)")
        }

        service.onChange = { [weak self] in self?.refresh() }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }

        // On the main run loop by name: this runs after an `await`, and `scheduledTimer` would pick the
        // current thread's run loop.
        let safetyNet = Timer(timeInterval: Self.safetyNetInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        safetyNet.tolerance = 60
        RunLoop.main.add(safetyNet, forMode: .default)
        self.safetyNet = safetyNet

        refresh()
    }

    func recheckAuthorization() {
        authorization = service.authorization
        refresh()
    }

    func refresh() {
        guard authorization == .authorized else {
            meetings = []
            calendars = []
            return
        }
        calendars = service.calendars()
        let now = Date()
        let fetched = service.meetings(
            from: now.addingTimeInterval(-Self.lookBehind),
            to: now.addingTimeInterval(Self.lookAhead),
            calendarIDs: preferences.enabledCalendarIDs
        )
        lastRefreshed = now
        let detected = fetched.map { meeting in
            var resolved = meeting
            resolved.joinURL = MeetingLinkDetector.joinURL(in: meeting)
            resolved.isOutOfOffice = OutOfOfficeDetector.isOutOfOffice(title: meeting.title, keywords: preferences.outOfOfficeKeywords)
            return resolved
        }
        // After the detectors: the out-of-office choice needs `isOutOfOffice`.
        meetings = MeetingFilter.visible(
            detected,
            eventsWithoutParticipants: preferences.eventsWithoutParticipants,
            outOfOfficeEvents: preferences.outOfOfficeEvents
        )
        // Events dismissed from the panel are forgotten once they end, at their ends as the calendar has them
        // now. The fetch holds every event still on, so one missing from it has ended, moved or gone, or its
        // calendar was unchecked; its entry stays until its stored end. A rule for all future events of a
        // repeating event stays until it's restored (`DismissedEvents.pruned`).
        let dismissed = preferences.dismissedEvents.pruned(at: now, meetings: fetched)
        if dismissed != preferences.dismissedEvents {
            preferences.dismissedEvents = dismissed
        }
    }

    /// The meetings that may produce full-screen alerts, drive the menu bar title and take the panel's card:
    /// those whose Events choice is Show and alert, less the ones dismissed from the panel, on their own or
    /// with all future events of their series (`DismissedEvents.isDismissed`). Reads both choices and the
    /// dismissed events, so observers (the alert coordinator, the menu bar item, the panel) follow them too:
    /// a dismissal cancels a pending alert and moves the menu bar on at once.
    var alertableMeetings: [Meeting] {
        MeetingFilter.alertable(
            meetings,
            eventsWithoutParticipants: preferences.eventsWithoutParticipants,
            outOfOfficeEvents: preferences.outOfOfficeEvents,
            dismissed: preferences.dismissedEvents
        )
    }

    /// The Show and alert meetings dismissed from the panel, by id, with how each was dismissed: the panel
    /// lists them as dismissed, with Restore, until they end. Restore asks This Event or All Future Events for
    /// one dismissed with its series (`.allFutureEvents`); one dismissed on its own restores at once.
    var dismissals: [Meeting.ID: DismissScope] {
        MeetingFilter.dismissals(
            meetings,
            eventsWithoutParticipants: preferences.eventsWithoutParticipants,
            outOfOfficeEvents: preferences.outOfOfficeEvents,
            dismissed: preferences.dismissedEvents
        )
    }

    var calendarsBySource: [(source: String, calendars: [CalendarInfo])] {
        var order: [String] = []
        var groups: [String: [CalendarInfo]] = [:]
        for calendar in calendars {
            if groups[calendar.sourceTitle] == nil { order.append(calendar.sourceTitle) }
            groups[calendar.sourceTitle, default: []].append(calendar)
        }
        return order.map { (source: $0, calendars: groups[$0] ?? []) }
    }
}
