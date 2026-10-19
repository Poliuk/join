import Foundation

/// What one notification says and offers, for a meeting or the demo: built here, posted by the app as it is.
/// The title is the event's title (macOS shows Join!'s name and icon above it, so it doesn't repeat them), the
/// subtitle its time range, and the body its calendar's name, then its location as the full-screen alert
/// shows it. Only clock times, never "Starts in 3 min": a delivered notification can't update, and macOS adds
/// its own "now" or "5m ago". It's posted Active, never Time Sensitive (an entitlement an ad-hoc-signed build
/// can't carry), and its previews follow the user's Show previews setting.
public struct NotificationContent: Equatable, Sendable {
    /// Every meeting's notification shares this thread, so meetings at the same time are grouped together.
    public static let threadIdentifier = "meetings"

    /// Its request's identifier: the same for a meeting's every send, so a snooze replaces it and moves it to
    /// the top.
    public let identifier: NotificationIdentifier
    /// "Design review".
    public let title: String
    /// "10:00 – 10:30 AM".
    public let subtitle: String
    /// "Work · Conference Room A", "Work", "Conference Room A", or empty; the test notification's says what it
    /// is (`DemoEvent.notificationBody`).
    public let body: String
    /// Which actions it offers (`NotificationCategory.actions`).
    public let category: NotificationCategory
    /// macOS's notification sound, or none (`NotificationSchedule.playsSound`).
    public let playsSound: Bool
    /// What a response needs without the calendar, which may not be read yet when a click launches Join!.
    public let payload: NotificationPayload

    /// The notification for `meeting`, as of `now`: At event start is offered only while its start is ahead.
    public static func meeting(
        _ meeting: Meeting,
        playsSound: Bool,
        now: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> NotificationContent {
        NotificationContent(
            .meeting(meeting.id), meeting: meeting, body: body(for: meeting),
            playsSound: playsSound, now: now, locale: locale, timeZone: timeZone
        )
    }

    /// Test Notification's notification: the demo event (`DemoEvent`), starting 3 minutes from `now`, with a body
    /// that says it's a test. Its actions only close it (`NotificationIdentifier.demo`), and withdrawals leave it
    /// alone.
    public static func demo(
        playsSound: Bool,
        now: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> NotificationContent {
        NotificationContent(
            .demo, meeting: DemoEvent.meeting(now: now), body: DemoEvent.notificationBody,
            playsSound: playsSound, now: now, locale: locale, timeZone: timeZone
        )
    }

    private init(
        _ identifier: NotificationIdentifier,
        meeting: Meeting,
        body: String,
        playsSound: Bool,
        now: Date,
        locale: Locale,
        timeZone: TimeZone
    ) {
        self.identifier = identifier
        title = meeting.title
        subtitle = MeetingTimeFormatter.timeRange(start: meeting.start, end: meeting.end, locale: locale, timeZone: timeZone)
        self.body = body
        category = NotificationCategory(meeting: meeting, now: now)
        self.playsSound = playsSound
        payload = NotificationPayload(meeting: meeting)
    }

    /// The calendar's name, then the location as the full-screen alert shows it; either alone when the other
    /// is missing.
    static func body(for meeting: Meeting) -> String {
        let calendar = meeting.calendarTitle.isEmpty ? nil : meeting.calendarTitle
        let location = LocationFormatter.alertLocation(meeting.location, joinURL: meeting.joinURL)
        return [calendar, location].compactMap { $0 }.joined(separator: " · ")
    }
}

/// A notification request's identifier: "meeting:<occurrence id>" for a meeting, "demo" for the demo.
public enum NotificationIdentifier: Hashable, Sendable, RawRepresentable {
    case meeting(Meeting.ID)
    case demo

    private static let meetingPrefix = "meeting:"
    private static let demoValue = "demo"

    /// Nil for an identifier Join! didn't make.
    public init?(rawValue: String) {
        if rawValue == Self.demoValue {
            self = .demo
        } else if rawValue.hasPrefix(Self.meetingPrefix), rawValue.count > Self.meetingPrefix.count {
            self = .meeting(String(rawValue.dropFirst(Self.meetingPrefix.count)))
        } else {
            return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .meeting(let id): return Self.meetingPrefix + id
        case .demo: return Self.demoValue
        }
    }
}

/// What a notification response needs to act without the calendar: the meeting's id, its link and its times.
/// Carried in the notification's `userInfo` as strings, which a property list holds and which are `Sendable`.
public struct NotificationPayload: Hashable, Sendable {
    public let meetingID: Meeting.ID
    public let joinURL: URL?
    public let start: Date
    public let end: Date

    enum Keys {
        static let meetingID = "meetingID"
        static let joinURL = "joinURL"
        static let start = "start"
        static let end = "end"
    }

    public init(meeting: Meeting) {
        meetingID = meeting.id
        joinURL = meeting.joinURL
        start = meeting.start
        end = meeting.end
    }

    /// Read back from a delivered notification's `userInfo`; nil when it isn't one of Join!'s.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let meetingID = userInfo[Keys.meetingID] as? String,
              let start = (userInfo[Keys.start] as? String).flatMap(TimeInterval.init),
              let end = (userInfo[Keys.end] as? String).flatMap(TimeInterval.init)
        else { return nil }
        self.meetingID = meetingID
        joinURL = (userInfo[Keys.joinURL] as? String).flatMap(URL.init(string:))
        self.start = Date(timeIntervalSince1970: start)
        self.end = Date(timeIntervalSince1970: end)
    }

    /// For the notification's `userInfo`: times as seconds since 1970, which read back exactly.
    public var userInfo: [String: String] {
        var info = [
            Keys.meetingID: meetingID,
            Keys.start: String(start.timeIntervalSince1970),
            Keys.end: String(end.timeIntervalSince1970),
        ]
        if let joinURL { info[Keys.joinURL] = joinURL.absoluteString }
        return info
    }
}

/// Which actions a notification offers, and its category identifier. macOS looks a category up when it shows a
/// notification and its buttons are fixed per category, so there is one for each combination: Join only with a
/// link, At event start only while the start is ahead. All four are registered at launch and again whenever
/// the snooze durations change.
public struct NotificationCategory: Hashable, Sendable {
    public let offersJoin: Bool
    public let offersAtEventStart: Bool

    public init(offersJoin: Bool, offersAtEventStart: Bool) {
        self.offersJoin = offersJoin
        self.offersAtEventStart = offersAtEventStart
    }

    /// For `meeting` as of `now`: Join when it has a link, At event start while it starts more than a second
    /// from now.
    public init(meeting: Meeting, now: Date) {
        self.init(
            offersJoin: meeting.joinURL != nil,
            offersAtEventStart: meeting.start > now.addingTimeInterval(AlertResponse.startingTolerance)
        )
    }

    /// Every category, to register at once: registering replaces the whole set.
    public static let all: [NotificationCategory] = [true, false].flatMap { join in
        [true, false].map { NotificationCategory(offersJoin: join, offersAtEventStart: $0) }
    }

    /// "meeting.join.atStart", "meeting.join", "meeting.atStart", "meeting".
    public var identifier: String {
        "meeting" + (offersJoin ? ".join" : "") + (offersAtEventStart ? ".atStart" : "")
    }

    /// Its actions, at most four: Join first, so it shows on a banner, then the snooze durations, each once
    /// (`AlertCountdown.snoozeChoices`: one action when both read the same), then At event start. None brings
    /// Join! to the front. macOS's own close button stands in for a Dismiss.
    public func actions(snoozeDurations: SnoozeDurations) -> [NotificationAction] {
        var responses: [AlertResponse] = offersJoin ? [.join] : []
        responses += AlertCountdown.snoozeChoices(snoozeDurations.all).map(AlertResponse.snooze)
        if offersAtEventStart { responses.append(.snoozeUntilStart) }
        return responses.compactMap(NotificationAction.init)
    }
}

/// One of a notification's actions: its identifier, which carries what it does, and its title.
public struct NotificationAction: Hashable, Sendable {
    public let identifier: String
    public let title: String
    public let response: AlertResponse

    /// Nil for `.close`, which a notification leaves to macOS's own close button.
    init?(_ response: AlertResponse) {
        guard let identifier = response.notificationActionIdentifier, let title = response.notificationActionTitle else { return nil }
        self.identifier = identifier
        self.title = title
        self.response = response
    }
}

extension AlertResponse {
    private static let joinIdentifier = "join"
    private static let snoozePrefix = "snooze."
    private static let atEventStartIdentifier = "atEventStart"

    /// The response to a notification action, from its identifier: "join", "snooze.60", "atEventStart". Nil
    /// for anything else, which Join! ignores: a click on the notification itself does nothing (the user's
    /// choice, 2026-10-16), and macOS's close button only closes it.
    public init?(notificationActionIdentifier identifier: String) {
        switch identifier {
        case Self.joinIdentifier:
            self = .join
        case Self.atEventStartIdentifier:
            self = .snoozeUntilStart
        default:
            guard identifier.hasPrefix(Self.snoozePrefix),
                  let seconds = Int(identifier.dropFirst(Self.snoozePrefix.count)), seconds > 0
            else { return nil }
            self = .snooze(TimeInterval(seconds))
        }
    }

    /// A snooze action's identifier holds its duration in whole minutes, as its title reads, so a response
    /// to a notification delivered before the durations changed still snoozes for what its action said.
    var notificationActionIdentifier: String? {
        switch self {
        case .join: return Self.joinIdentifier
        case .snooze(let duration): return Self.snoozePrefix + String(Self.wholeMinutes(duration) * 60)
        case .snoozeUntilStart: return Self.atEventStartIdentifier
        case .close: return nil
        }
    }

    /// "Join", "Snooze 1 min", "At event start": the full-screen alert's words, with "Snooze" spelled out,
    /// since a notification has no Snooze label beside its buttons.
    var notificationActionTitle: String? {
        switch self {
        case .join: return AlertCountdown.joinTitle(for: .before)
        case .snooze(let duration): return "Snooze " + AlertCountdown.snoozeLabel(duration)
        case .snoozeUntilStart: return AlertCountdown.snoozeUntilStartLabel
        case .close: return nil
        }
    }

    private static func wholeMinutes(_ duration: TimeInterval) -> Int {
        max(1, Int((duration / 60).rounded()))
    }
}
