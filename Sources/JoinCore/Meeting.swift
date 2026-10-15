import Foundation

/// Your answer to the invitation. Events without attendees, and ones you organize, count as accepted;
/// `unknown` covers invitations you haven't answered and events you aren't invited to.
public enum ParticipationStatus: String, Hashable, Sendable {
    case accepted
    case tentative
    case declined
    case unknown
}

/// One occurrence of a calendar event, independent of the calendar backend.
public struct Meeting: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarID: String
    public var calendarTitle: String
    public var calendarColor: RGBA
    public var location: String?
    public var notes: String?
    public var url: URL?
    public var myStatus: ParticipationStatus
    /// Someone other than you is on the event: an attendee who isn't you, or an organizer who isn't you.
    /// False for focus blocks and reminders you add for yourself, which Settings has a choice for.
    public var hasParticipants: Bool
    public var joinURL: URL?
    /// Set by the detector; Settings has a choice for such events.
    public var isOutOfOffice: Bool
    /// The repeating event this is an occurrence of, shared by all its occurrences, one edited on its own
    /// included (EventKit's event identifier, the part of `id` before "@"); nil for an event that doesn't
    /// repeat. Dismissing all future events of a series goes by it (`DismissedEvents`).
    public var seriesID: String?

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        calendarID: String = "",
        calendarTitle: String = "",
        calendarColor: RGBA = RGBA(red: 0.2, green: 0.5, blue: 0.9),
        location: String? = nil,
        notes: String? = nil,
        url: URL? = nil,
        myStatus: ParticipationStatus = .accepted,
        hasParticipants: Bool = true,
        joinURL: URL? = nil,
        isOutOfOffice: Bool = false,
        seriesID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.calendarColor = calendarColor
        self.location = location
        self.notes = notes
        self.url = url
        self.myStatus = myStatus
        self.hasParticipants = hasParticipants
        self.joinURL = joinURL
        self.isOutOfOffice = isOutOfOffice
        self.seriesID = seriesID
    }

    /// Recurring events share one event identifier, so the occurrence start is part of the id.
    public static func occurrenceID(eventIdentifier: String, start: Date) -> String {
        "\(eventIdentifier)@\(Int(start.timeIntervalSince1970))"
    }

    /// One occurrence of a repeating event: dismissing or restoring it asks whether to act on this event or
    /// on all future events (`DismissScope`).
    public var isRepeating: Bool { seriesID != nil }

    /// You said yes, or it's your own event. Maybe and unanswered invitations don't count.
    public var isAttending: Bool { myStatus == .accepted }

    public func isOngoing(at now: Date) -> Bool { start <= now && now < end }
    public func isUpcoming(at now: Date) -> Bool { start > now }
    public func hasEnded(at now: Date) -> Bool { end <= now }
}

/// Decides which calendar events are worth alerting about.
public enum MeetingFilter {
    public static func shouldInclude(isAllDay: Bool, isCanceled: Bool, myStatus: ParticipationStatus) -> Bool {
        if isAllDay || isCanceled { return false }
        return myStatus != .declined
    }

    /// The Settings › General › Events choice that applies to `meeting`: the one for its kind, the one that
    /// shows less when it is both kinds, and `.showAndAlert` for any other event. Needs `isOutOfOffice` set.
    public static func visibility(
        of meeting: Meeting,
        eventsWithoutParticipants: EventVisibility,
        outOfOfficeEvents: EventVisibility
    ) -> EventVisibility {
        var choice = EventVisibility.showAndAlert
        if !meeting.hasParticipants { choice = min(choice, eventsWithoutParticipants) }
        if meeting.isOutOfOffice { choice = min(choice, outOfOfficeEvents) }
        return choice
    }

    /// The meetings the panel lists, and the only ones Join! uses anywhere: excluded ones are left out,
    /// like the events of an unchecked calendar. Keeps the order.
    public static func visible(
        _ meetings: [Meeting],
        eventsWithoutParticipants: EventVisibility,
        outOfOfficeEvents: EventVisibility
    ) -> [Meeting] {
        meetings.filter {
            visibility(of: $0, eventsWithoutParticipants: eventsWithoutParticipants, outOfOfficeEvents: outOfOfficeEvents).isListed
        }
    }

    /// The meetings that may alert, drive the menu bar item and take the panel's card: those whose choice
    /// is Show and alert, less the ones the user dismissed from the panel (`DismissedEvents.isDismissed`:
    /// on their own or with all future events of their series), always a subset of `visible`. Keeps the order.
    public static func alertable(
        _ meetings: [Meeting],
        eventsWithoutParticipants: EventVisibility,
        outOfOfficeEvents: EventVisibility,
        dismissed: DismissedEvents = DismissedEvents()
    ) -> [Meeting] {
        meetings.filter {
            !dismissed.isDismissed($0)
                && visibility(of: $0, eventsWithoutParticipants: eventsWithoutParticipants, outOfOfficeEvents: outOfOfficeEvents).alerts
        }
    }

    /// The Show and alert meetings the user dismissed, by id, with how each was dismissed: with its series
    /// (`.allFutureEvents`: a rule of the series covers it, `DismissedEvents.isDismissedBySeries`, so its
    /// Restore asks This Event or All Future Events) or on its own (`.thisEvent`). Left out of `alertable`,
    /// and listed by the panel as dismissed, with Restore, until they end. Only an event that could alert can
    /// be dismissed, so one whose choice has since become Show in the list only is listed like any other of
    /// its kind: it isn't here.
    public static func dismissals(
        _ meetings: [Meeting],
        eventsWithoutParticipants: EventVisibility,
        outOfOfficeEvents: EventVisibility,
        dismissed: DismissedEvents
    ) -> [Meeting.ID: DismissScope] {
        guard !dismissed.isEmpty else { return [:] }
        var dismissals: [Meeting.ID: DismissScope] = [:]
        for meeting in meetings where dismissed.isDismissed(meeting)
            && visibility(of: meeting, eventsWithoutParticipants: eventsWithoutParticipants, outOfOfficeEvents: outOfOfficeEvents).alerts {
            // The same occurrence twice in a fetch: with its series on either copy, its Restore asks.
            if dismissals[meeting.id] == .allFutureEvents { continue }
            dismissals[meeting.id] = dismissed.isDismissedBySeries(meeting) ? .allFutureEvents : .thisEvent
        }
        return dismissals
    }
}
