import Foundation

/// What one notification card says, for a meeting or Test Notification's demo event. Join! draws the card
/// itself, a small window at the top right of the screen (the user's choice, 2026-10-19: macOS folds two or
/// more notification actions into one "Options" pull-down, so its notification couldn't show a Join button).
/// The title, then the countdown and the time range, then the location, or the test card's note: never the
/// calendar's name, which for an account's calendar is often the user's email address. The countdown is
/// worded for a moment (`countdown(now:)`), so the card updates it as time passes; the rest stays.
public struct NotificationCard: Identifiable, Equatable, Sendable {
    /// The card's window title, which VoiceOver and the snapshot hook read, the same on every card.
    public static let windowTitle = "Join! notification"

    /// The card's size, in points: 60 tall, 76 with a third line (`detail`).
    public static let width = 380.0
    public static let compactHeight = 60.0
    public static let detailHeight = 76.0

    /// The third line, under the time line.
    public enum Detail: Equatable, Sendable {
        /// "Conference Room A", after a map pin: the location as the full-screen alert shows it.
        case location(String)
        /// The test card's "This is a test notification.", without the pin.
        case note(String)

        public var text: String {
            switch self {
            case .location(let text), .note(let text): return text
            }
        }
    }

    /// The meeting it's for: the demo event's for the test card.
    public let meeting: Meeting
    /// Test Notification's card: its Join opens the demo event's link, every other choice only closes it,
    /// and nothing withdraws it or changes a real meeting's state.
    public let isTest: Bool
    /// "10:00 – 10:30 AM".
    public let timeRange: String
    public let detail: Detail?

    public var id: Meeting.ID { meeting.id }
    /// "Design review".
    public var title: String { meeting.title }
    /// A split button of Join and a menu with a link; only the menu, "Snooze", without one.
    public var joinURL: URL? { meeting.joinURL }
    public var height: Double { detail == nil ? Self.compactHeight : Self.detailHeight }

    /// The card for `meeting`.
    public static func meeting(_ meeting: Meeting, locale: Locale = .current, timeZone: TimeZone = .current) -> NotificationCard {
        let location = LocationFormatter.alertLocation(meeting.location, joinURL: meeting.joinURL)
        return NotificationCard(meeting, isTest: false, detail: location.map(Detail.location), locale: locale, timeZone: timeZone)
    }

    /// Test Notification's card: the demo event (`DemoEvent`), starting 3 minutes from `now`, with a note that
    /// says it's a test where a meeting's card has its location.
    public static func test(now: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> NotificationCard {
        NotificationCard(
            DemoEvent.meeting(now: now), isTest: true, detail: .note(DemoEvent.notificationNote), locale: locale, timeZone: timeZone
        )
    }

    private init(_ meeting: Meeting, isTest: Bool, detail: Detail?, locale: Locale, timeZone: TimeZone) {
        self.meeting = meeting
        self.isTest = isTest
        timeRange = MeetingTimeFormatter.timeRange(start: meeting.start, end: meeting.end, locale: locale, timeZone: timeZone)
        self.detail = detail
    }

    /// The countdown at `now`, with the Join button's title.
    public func countdown(now: Date) -> Countdown {
        Countdown(start: meeting.start, now: now)
    }

    // MARK: Accessibility

    /// The card's text as one element: "Design review, starts in 5 minutes, 10:00 to 10:30 AM, Conference Room A".
    public func accessibilityLabel(now: Date) -> String {
        [title, countdown(now: now).spokenText, Self.spokenRange(timeRange), detail?.text]
            .compactMap(\.self)
            .joined(separator: ", ")
    }

    /// Posted when the card appears, since a window of an app that isn't active gets no VoiceOver focus:
    /// "Join!: Design review starts in 5 minutes.", "…is starting now.", "…started 3 minutes ago."
    public func announcement(now: Date) -> String {
        "Join!: \(title) \(countdown(now: now).announcedText)."
    }

    /// The Join segment: "Join video call: Design review".
    public var joinAccessibilityLabel: String { "Join video call: \(title)" }
    /// The chevron segment, or the Snooze pull-down without a link: "Snooze or dismiss Design review".
    public var menuAccessibilityLabel: String { "Snooze or dismiss \(title)" }
    /// The × at the top left: "Dismiss notification: Design review".
    public var closeAccessibilityLabel: String { "Dismiss notification: \(title)" }

    /// The pull-down's title on a card without a link, where the menu is the only control.
    public static let snoozeMenuTitle = "Snooze"

    /// Help tags, shown while Join! isn't active too.
    public static let joinHelp = "Opens the video call. No more alerts for this event."
    public static let menuHelp = "Snooze or dismiss"
    public static let closeHelp = "Dismiss"

    /// "10:00 to 10:30 AM": VoiceOver reads the dash as "dash".
    static func spokenRange(_ range: String) -> String {
        range.replacingOccurrences(of: "\\s*–\\s*", with: " to ", options: .regularExpression)
    }
}

extension NotificationCard {
    /// The time line's first part, its color, and the Join button's title, at one moment. Whole minutes,
    /// rounded up before the start, so it never reads "Starts in 0 min": "Starts in 5 min" … "Starts in 1 min",
    /// "Starting now" for the first minute after the start, then "Started 3 min ago", rounded down, as the
    /// full-screen alert counts.
    public struct Countdown: Equatable, Sendable {
        public enum Tone: Equatable, Sendable {
            /// The panel's accent text, as its "Starts in 4 min".
            case accent
            /// The panel's warning orange: the meeting has started without the user.
            case warning
        }

        /// "Starts in 5 min", "Starting now", "Started 3 min ago".
        public let text: String
        public let tone: Tone
        /// "Join", then "Join now" from the start, as on the full-screen alert.
        public let joinTitle: String
        /// "starts in 5 minutes", "starting now", "started 3 minutes ago": the card's text element.
        public let spokenText: String
        /// "starts in 5 minutes", "is starting now", "started 3 minutes ago": after the title, in the announcement.
        public let announcedText: String

        init(start: Date, now: Date) {
            // A card's meeting that ends is withdrawn, so its end plays no part.
            let phase = AlertCountdown.phase(start: start, end: .distantFuture, now: now)
            joinTitle = AlertCountdown.joinTitle(for: phase)
            switch phase {
            case .before:
                // The small tolerance keeps floating-point noise on an exact minute from adding a minute.
                let minutes = max(1, Int((start.timeIntervalSince(now) / 60 - 0.001).rounded(.up)))
                text = "Starts in \(AlertCountdown.minutesText(minutes: minutes))"
                tone = .accent
                spokenText = "starts in \(Self.spokenMinutes(minutes))"
                announcedText = spokenText
            case .starting:
                text = "Starting now"
                tone = .accent
                spokenText = "starting now"
                announcedText = "is starting now"
            case .started, .ended:
                let minutes = max(1, Int(now.timeIntervalSince(start) / 60))
                text = "Started \(AlertCountdown.minutesText(minutes: minutes)) ago"
                tone = .warning
                spokenText = "started \(Self.spokenMinutes(minutes)) ago"
                announcedText = spokenText
            }
        }

        /// "1 minute", "5 minutes", "1 hour", "1 hour 30 minutes".
        static func spokenMinutes(_ minutes: Int) -> String {
            let hours = minutes / 60
            let rest = minutes % 60
            let restText = SettingsOptions.durationTitle(minutes: rest)
            guard hours > 0 else { return restText }
            let hoursText = SettingsOptions.durationTitle(minutes: hours * 60)
            return rest == 0 ? hoursText : "\(hoursText) \(restText)"
        }
    }
}

/// The menu under a card's chevron, or its Snooze pull-down: the Snooze box's two times, each once, At event
/// start while the start is ahead, a separator, then Dismiss. A standard macOS menu, at least `minimumWidth`
/// wide, `gap` under the button with their right edges aligned. What's offered is decided as it opens.
public struct NotificationMenu: Equatable, Sendable {
    public static let minimumWidth = 180.0
    public static let gap = 4.0

    /// "Snooze 1 min", "Snooze 5 min", then "At event start" while the meeting starts more than a second from
    /// now.
    public let snoozes: [NotificationMenuItem]
    /// After a separator: closes the card for good, leaving the full-screen alert to come.
    public let dismiss: NotificationMenuItem

    /// `fullScreenAlertsEnabled` is Alert me having a time: only then does Dismiss's help tag say the
    /// full-screen alert still comes, and never on the test card, which has none.
    public init(
        for card: NotificationCard,
        snoozeDurations: SnoozeDurations,
        fullScreenAlertsEnabled: Bool,
        now: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        var snoozes = AlertCountdown.snoozeChoices(snoozeDurations.all).map { duration in
            NotificationMenuItem(
                response: .snooze(duration),
                title: "Snooze " + AlertCountdown.snoozeLabel(duration),
                accessibilityLabel: AlertCountdown.snoozeAccessibilityLabel(duration),
                help: nil
            )
        }
        let start = card.meeting.start
        if start > now.addingTimeInterval(AlertResponse.startingTolerance) {
            let time = MeetingTimeFormatter.shortTime(start, locale: locale, timeZone: timeZone)
            snoozes.append(NotificationMenuItem(
                response: .snoozeUntilStart,
                title: AlertCountdown.snoozeUntilStartLabel,
                accessibilityLabel: AlertCountdown.snoozeUntilStartAccessibilityLabel(start, locale: locale, timeZone: timeZone),
                help: "Comes back at \(time)."
            ))
        }
        self.snoozes = snoozes
        let alertComes = fullScreenAlertsEnabled && !card.isTest
        dismiss = NotificationMenuItem(
            response: .close,
            title: Self.dismissTitle,
            accessibilityLabel: Self.dismissTitle,
            help: alertComes ? Self.dismissHelp + " " + Self.fullScreenAlertStillComes : Self.dismissHelp
        )
    }

    static let dismissTitle = "Dismiss"
    static let dismissHelp = "Closes this notification."
    static let fullScreenAlertStillComes = "The full-screen alert still comes at its time."
}

/// One choice in a card's menu.
public struct NotificationMenuItem: Equatable, Sendable {
    /// What choosing it does, for this kind only (`AlertResponse.state`): a snooze, At event start, or close.
    public let response: AlertResponse
    public let title: String
    /// What VoiceOver says, with what the title leaves out: "Snooze 5 minutes".
    public let accessibilityLabel: String
    /// The help tag, if any.
    public let help: String?
}

/// How the cards stack at the top right of a screen: one per meeting, soonest on top, `spacing` apart, at
/// most `maximumPerScreen`, the rest waiting for a slot. A card on screen keeps its slot until it goes: a card
/// that comes later waits, even for a meeting that starts sooner, and never pushes one off.
public enum NotificationStack {
    public static let maximumPerScreen = 3
    /// Between cards, and from the screen's right edge and the menu bar.
    public static let spacing = 8.0
    public static let screenMargin = 12.0

    /// Soonest first; meetings that start together by title, then by id, so the order never flips.
    public static func ordered(_ cards: [NotificationCard]) -> [NotificationCard] {
        cards.sorted { lhs, rhs in
            if lhs.meeting.start != rhs.meeting.start { return lhs.meeting.start < rhs.meeting.start }
            switch lhs.title.localizedStandardCompare(rhs.title) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return lhs.id < rhs.id
            }
        }
    }

    /// The cards one screen shows, top to bottom, and those waiting, in the order they'll come: of `cards`
    /// (every card due on the screen), those already on it (`shown`) stay, and the free slots go to the others,
    /// soonest first.
    public static func arrange(_ cards: [NotificationCard], shown: Set<Meeting.ID>) -> (shown: [NotificationCard], waiting: [NotificationCard]) {
        let ordered = ordered(cards)
        var slots = maximumPerScreen - ordered.filter { shown.contains($0.id) }.count
        var showing: [NotificationCard] = []
        var waiting: [NotificationCard] = []
        for card in ordered {
            if shown.contains(card.id) {
                showing.append(card)
            } else if slots > 0 {
                showing.append(card)
                slots -= 1
            } else {
                waiting.append(card)
            }
        }
        return (showing, waiting)
    }

    /// Each card's top, down from the stack's top, for cards of these heights, top to bottom.
    public static func offsets(heights: [Double]) -> [Double] {
        heights.indices.map { index in
            heights[..<index].reduce(0, +) + Double(index) * spacing
        }
    }

    /// How far the stack's top is under the screen's top edge: the menu bar, measured as the largest of the
    /// safe area's top (the notch), the menu bar's thickness and what the visible frame leaves out at the top,
    /// then `screenMargin`. The same with the menu bar shown, auto-hidden or in a full-screen Space, so the cards
    /// don't jump when it slides in.
    public static func topInset(safeAreaTop: Double, menuBarThickness: Double, reservedTop: Double) -> Double {
        max(safeAreaTop, menuBarThickness, reservedTop) + screenMargin
    }
}
