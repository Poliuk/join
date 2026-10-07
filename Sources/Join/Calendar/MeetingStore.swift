import AppKit
import Observation
import OSLog
import JoinCore

private let logger = Logger(subsystem: "com.poliuk.join", category: "calendar")

/// Single source of truth for the meetings the rest of the app sees.
@MainActor
@Observable
final class MeetingStore {
    static let lookBehind: TimeInterval = 60 * 60
    static let lookAhead: TimeInterval = 7 * 24 * 60 * 60
    static let safetyNetInterval: TimeInterval = 15 * 60

    /// The events from the checked calendars, without those with no participants while Settings hides them.
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
        logger.notice("Calendar authorization at launch: \(String(describing: self.authorization), privacy: .public)")
        if authorization == .notDetermined {
            _ = await service.requestAccess()
            authorization = service.authorization
            logger.notice("Calendar authorization after request: \(String(describing: self.authorization), privacy: .public)")
        }

        service.onChange = { [weak self] in self?.refresh() }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }

        safetyNet = Timer.scheduledTimer(withTimeInterval: Self.safetyNetInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        safetyNet?.tolerance = 60

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
        let visible = MeetingFilter.visible(fetched, showsEventsWithoutParticipants: preferences.showsEventsWithoutParticipants)
        meetings = visible.map { meeting in
            var resolved = meeting
            resolved.joinURL = MeetingLinkDetector.joinURL(in: meeting)
            resolved.isOutOfOffice = OutOfOfficeDetector.isOutOfOffice(title: meeting.title, keywords: preferences.outOfOfficeKeywords)
            return resolved
        }
    }

    /// The meetings that may produce alerts and drive the menu bar title.
    var alertableMeetings: [Meeting] {
        MeetingFilter.alertable(meetings, alertForOutOfOffice: preferences.alertForOutOfOffice)
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
