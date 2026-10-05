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

    private(set) var meetings: [Meeting] = []
    private(set) var calendars: [CalendarInfo] = []
    private(set) var authorization: CalendarAuthorization = .notDetermined

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
        meetings = fetched.map { meeting in
            var resolved = meeting
            resolved.joinURL = MeetingLinkDetector.joinURL(in: meeting)
            resolved.isOutOfOffice = OutOfOfficeDetector.isOutOfOffice(title: meeting.title, keywords: preferences.outOfOfficeKeywords)
            return resolved
        }
    }

    /// The meetings that may produce alerts and drive the menu bar title.
    var alertableMeetings: [Meeting] {
        preferences.alertForOutOfOffice ? meetings : meetings.filter { !$0.isOutOfOffice }
    }

    func ongoing(at now: Date) -> [Meeting] {
        meetings.filter { $0.isOngoing(at: now) }
    }

    func upcoming(at now: Date, todayOnly: Bool, calendar: Calendar = .current) -> [Meeting] {
        meetings.filter { meeting in
            guard meeting.isUpcoming(at: now) else { return false }
            return todayOnly ? calendar.isDate(meeting.start, inSameDayAs: now) : true
        }
    }

    func current(at now: Date) -> Meeting? {
        alertableMeetings.first { $0.isOngoing(at: now) }
    }

    func next(at now: Date) -> Meeting? {
        alertableMeetings.first { $0.isUpcoming(at: now) }
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
