import AppKit
import EventKit
import JoinCore

@MainActor
final class EventKitCalendarService: CalendarService {
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    var onChange: (@MainActor () -> Void)?

    init() {
        startObserving()
    }

    private func startObserving() {
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onChange?() }
        }
    }

    var authorization: CalendarAuthorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .fullAccess, .authorized: return .authorized
        case .writeOnly: return .writeOnly
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    func calendars() -> [CalendarInfo] {
        store.calendars(for: .event)
            .map { calendar in
                CalendarInfo(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    sourceTitle: calendar.source?.title ?? "Other",
                    color: Self.rgba(from: calendar.cgColor)
                )
            }
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
    }

    func meetings(from start: Date, to end: Date, calendarIDs: Set<String>?) -> [Meeting] {
        var calendars: [EKCalendar]?
        if let calendarIDs {
            let selected = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
            if selected.isEmpty { return [] }
            calendars = selected
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .compactMap(Self.meeting(from:))
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    static func meeting(from event: EKEvent) -> Meeting? {
        let myStatus = participationStatus(for: event)
        guard MeetingFilter.shouldInclude(isAllDay: event.isAllDay, isCanceled: event.status == .canceled, myStatus: myStatus),
              let start = event.startDate, let end = event.endDate
        else { return nil }

        let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
        return Meeting(
            id: Meeting.occurrenceID(eventIdentifier: identifier, start: start),
            title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled event",
            start: start,
            end: end,
            isAllDay: event.isAllDay,
            calendarID: event.calendar.calendarIdentifier,
            calendarTitle: event.calendar.title,
            calendarColor: rgba(from: event.calendar.cgColor),
            location: event.location?.nilIfEmpty,
            notes: event.notes?.nilIfEmpty,
            url: event.url,
            myStatus: myStatus
        )
    }

    private static func participationStatus(for event: EKEvent) -> ParticipationStatus {
        guard let attendees = event.attendees, !attendees.isEmpty else { return .accepted }
        guard let me = attendees.first(where: { $0.isCurrentUser }) else { return .unknown }
        switch me.participantStatus {
        case .accepted: return .accepted
        case .tentative: return .tentative
        case .declined: return .declined
        default: return .unknown
        }
    }

    private static func rgba(from cgColor: CGColor?) -> RGBA {
        guard let cgColor, let color = NSColor(cgColor: cgColor) else {
            return RGBA(red: 0.2, green: 0.5, blue: 0.9)
        }
        return color.rgba
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
