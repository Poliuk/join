import Foundation

/// Your answer to the invitation. Events without attendees, and ones you organize, count as accepted;
/// `unknown` covers invitations you haven't answered and events you aren't invited to.
public enum ParticipationStatus: String, Codable, Hashable, Sendable {
    case accepted
    case tentative
    case declined
    case unknown
}

/// One occurrence of a calendar event, independent of the calendar backend.
public struct Meeting: Identifiable, Hashable, Sendable, Codable {
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
    /// False for focus blocks and reminders you add for yourself, which Settings can hide.
    public var hasParticipants: Bool
    public var joinURL: URL?
    /// Set by the detector; such events can be excluded from alerts in Settings.
    public var isOutOfOffice: Bool

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
        isOutOfOffice: Bool = false
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
    }

    /// Recurring events share one event identifier, so the occurrence start is part of the id.
    public static func occurrenceID(eventIdentifier: String, start: Date) -> String {
        "\(eventIdentifier)@\(Int(start.timeIntervalSince1970))"
    }

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

    /// The meetings Join! uses anywhere: the panel, the menu bar and alerts. With the switch off, events
    /// nobody else is on are left out, like the events of an unchecked calendar, whether or not they look
    /// out of office. Keeps the order.
    public static func visible(_ meetings: [Meeting], showsEventsWithoutParticipants: Bool) -> [Meeting] {
        showsEventsWithoutParticipants ? meetings : meetings.filter(\.hasParticipants)
    }

    /// The visible meetings that may alert and drive the menu bar: out-of-office ones only when Settings
    /// says so. Takes the output of `visible`, so a hidden event never comes back here.
    public static func alertable(_ visibleMeetings: [Meeting], alertForOutOfOffice: Bool) -> [Meeting] {
        alertForOutOfOffice ? visibleMeetings : visibleMeetings.filter { !$0.isOutOfOffice }
    }
}
