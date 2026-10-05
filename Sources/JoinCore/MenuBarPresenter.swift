import Foundation

/// What the menu bar item shows: its icon, optional text, and how it is drawn.
public struct MenuBarStatus: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Nothing upcoming: the calendar icon alone.
        case idle
        /// Reminders paused: the crossed-out bell, never any text.
        case paused
        /// The next meeting is more than an hour away: "1:00 PM", "Tomorrow 1:00 PM", "Wednesday 1:00 PM",
        /// "Mon 12 Oct 9:00 AM" a week ahead.
        case later
        /// The next meeting starts within the hour: "in 42 min".
        case withinHour
        /// A meeting starts in five minutes or less: drawn as an accent-filled pill.
        case startingSoon
        /// In a meeting: a ring that drains as it runs; `remaining` goes from 1 at the start to 0 at the end.
        case inMeeting(remaining: Double)
    }

    public var kind: Kind
    /// nil means icon only.
    public var text: String?
    public var accessibilityLabel: String

    public init(kind: Kind, text: String?, accessibilityLabel: String) {
        self.kind = kind
        self.text = text
        self.accessibilityLabel = accessibilityLabel
    }
}

/// Pure presentation logic for the menu bar item and the shared wording of the menu bar panel.
public enum MenuBarPresenter {
    public static let startingSoonWindow: TimeInterval = 5 * 60
    public static let withinHourWindow: TimeInterval = 60 * 60
    public static let maxTitleLength = 24

    /// Precedence: paused > starting soon > in a meeting > within the hour > later.
    /// `meetings` are the alertable ones: out-of-office blocks never drive the menu bar unless the user opted in.
    public static func status(
        meetings: [Meeting],
        now: Date,
        pauseState: PauseState,
        showsNextEvent: Bool,
        showsTitles: Bool,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> MenuBarStatus {
        if pauseState.isPaused(at: now) {
            return MenuBarStatus(kind: .paused, text: nil, accessibilityLabel: "Join!: reminders paused")
        }

        func compose(_ kind: MenuBarStatus.Kind, _ text: String, meeting: Meeting, spoken: String) -> MenuBarStatus {
            let shown: String? = showsNextEvent
                ? (showsTitles ? "\(MeetingTimeFormatter.truncate(meeting.title, to: maxTitleLength)) · \(text)" : text)
                : nil
            return MenuBarStatus(kind: kind, text: shown, accessibilityLabel: "Join!: \(meeting.title) \(spoken)")
        }

        let next = nextMeeting(in: meetings, now: now)
        if let next, next.start.timeIntervalSince(now) <= startingSoonWindow {
            let until = next.start.timeIntervalSince(now)
            return compose(.startingSoon, "in \(minutes(until))", meeting: next, spoken: "starts in \(spokenDuration(until))")
        }
        if let current = currentMeeting(in: meetings, now: now) {
            let left = current.end.timeIntervalSince(now)
            return compose(
                .inMeeting(remaining: remainingFraction(of: current, now: now)),
                "\(duration(left)) left",
                meeting: current,
                spoken: "ends in \(spokenDuration(left))"
            )
        }
        guard let next else {
            return MenuBarStatus(kind: .idle, text: nil, accessibilityLabel: "Join!: no upcoming meetings")
        }
        let until = next.start.timeIntervalSince(now)
        if until <= withinHourWindow {
            return compose(.withinHour, "in \(minutes(until))", meeting: next, spoken: "in \(spokenDuration(until))")
        }
        let time = shortTime(next.start, calendar: calendar, locale: locale)
        if calendar.isDate(next.start, inSameDayAs: now) {
            return compose(.later, time, meeting: next, spoken: "at \(time)")
        }
        let day = relativeDay(next.start, now: now, calendar: calendar, locale: locale)
        let spokenDay = relativeDay(next.start, now: now, calendar: calendar, locale: locale, spoken: true)
        return compose(.later, "\(capitalizingFirst(day)) \(time)", meeting: next, spoken: "\(spokenDay) at \(time)")
    }

    /// The earliest meeting that hasn't started yet.
    public static func nextMeeting(in meetings: [Meeting], now: Date) -> Meeting? {
        meetings
            .filter { $0.start > now }
            .min { ($0.start, $0.title, $0.id) < ($1.start, $1.title, $1.id) }
    }

    /// The ongoing meeting that started most recently: the one you most likely just joined.
    public static func currentMeeting(in meetings: [Meeting], now: Date) -> Meeting? {
        meetings
            .filter { $0.isOngoing(at: now) }
            .max { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                if lhs.end != rhs.end { return lhs.end > rhs.end }
                return (lhs.title, lhs.id) > (rhs.title, rhs.id)
            }
    }

    /// 1 when the meeting starts, 0 when it ends.
    public static func remainingFraction(of meeting: Meeting, now: Date) -> Double {
        let total = meeting.end.timeIntervalSince(meeting.start)
        guard total > 0 else { return 0 }
        return min(max(meeting.end.timeIntervalSince(now) / total, 0), 1)
    }

    /// 0 when the meeting starts, 1 when it ends.
    public static func elapsedFraction(of meeting: Meeting, now: Date) -> Double {
        1 - remainingFraction(of: meeting, now: now)
    }

    /// Whole minutes, rounded up so a countdown never reads "0 min" before the start: "42 min", "2 h 15 min", "3 h".
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = wholeMinutes(seconds)
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) h" : "\(hours) h \(remainder) min"
    }

    /// Minutes only, for countdowns within the hour: "42 min", "60 min".
    public static func minutes(_ seconds: TimeInterval) -> String {
        "\(wholeMinutes(seconds)) min"
    }

    /// The same duration, spelled out for VoiceOver: "4 minutes", "1 hour 5 minutes".
    public static func spokenDuration(_ seconds: TimeInterval) -> String {
        let minutes = wholeMinutes(seconds)
        func unit(_ value: Int, _ singular: String) -> String { "\(value) \(singular)\(value == 1 ? "" : "s")" }
        if minutes < 60 { return unit(minutes, "minute") }
        let hours = unit(minutes / 60, "hour")
        return minutes % 60 == 0 ? hours : "\(hours) \(unit(minutes % 60, "minute"))"
    }

    /// "Reminders paused until 11:50 AM", "Reminders paused until tomorrow", "Reminders paused", or nil.
    public static func pausedMessage(
        _ state: PauseState,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String? {
        switch state.resolved(at: now) {
        case .active:
            return nil
        case .indefinitely:
            return "Reminders paused"
        case .until(let end):
            let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            if end == startOfTomorrow { return "Reminders paused until tomorrow" }
            return "Reminders paused until \(shortTime(end, calendar: calendar, locale: locale))"
        }
    }

    /// The panel header: "Tuesday, 6 October" (localized).
    public static func headerDate(_ now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        formatter(template: "EEEEdMMMM", calendar: calendar, locale: locale).string(from: now)
    }

    /// "tomorrow", the weekday ("Wednesday") within the coming week, or the date ("Mon 12 Oct", localized) a week
    /// or more ahead, where a bare weekday would read as today. `spoken` spells the date out for VoiceOver.
    static func relativeDay(_ date: Date, now: Date, calendar: Calendar, locale: Locale, spoken: Bool = false) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        if days == 1 { return "tomorrow" }
        let template = days < 7 ? "EEEE" : (spoken ? "EEEEdMMMM" : "EEEdMMM")
        return formatter(template: template, calendar: calendar, locale: locale).string(from: date)
    }

    static func shortTime(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        MeetingTimeFormatter.shortTime(date, locale: locale, timeZone: calendar.timeZone)
    }

    static func formatter(template: String, calendar: Calendar, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    static func capitalizingFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    private static func wholeMinutes(_ seconds: TimeInterval) -> Int {
        // The small tolerance keeps floating-point noise on an exact minute from rounding up a whole extra minute.
        max(0, Int((seconds / 60 - 0.001).rounded(.up)))
    }
}
