import Foundation

/// What a meeting's button in the menu bar panel does.
public enum PanelAction: Hashable, Sendable {
    case join(URL)
    case directions(URL)
}

/// The menu bar panel below its header: one hero card, then sections of rows.
public struct PanelContent: Equatable, Sendable {
    public var hero: PanelHero
    public var sections: [PanelSection]

    public init(hero: PanelHero, sections: [PanelSection]) {
        self.hero = hero
        self.sections = sections
    }

    /// The list as the panel's Today | 7 Days switch shows it. The hero card never depends on it.
    public func filtered(by choice: PanelListFilter) -> PanelFilterState {
        let today = sections.filter { $0.kind != .later }
        let isTodayAvailable = today.contains { section in section.rows.contains { !$0.isMuted } }
        let effective: PanelListFilter = choice == .today && isTodayAvailable ? .today : .week
        return PanelFilterState(
            isShown: sections.contains { $0.kind == .later },
            isTodayAvailable: isTodayAvailable,
            effective: effective,
            sections: effective == .today ? today : sections
        )
    }
}

/// The choice behind the panel's Today | 7 Days switch.
public enum PanelListFilter: String, CaseIterable, Sendable {
    /// What's on now and what's still to start today.
    case today
    /// Today, then each following day in the 7-day window.
    case week
}

/// The Today | 7 Days switch for one moment's content.
public struct PanelFilterState: Equatable, Sendable {
    /// False when nothing comes after today: both choices would list the same rows, so the switch hides.
    public var isShown: Bool
    /// False when nothing is left today but out-of-office blocks (evenings, the day's last meeting): Today
    /// is dimmed and the week shows, so Today never leads to an empty list. The stored choice is kept, so
    /// Today comes back by itself the next morning. Dismissed events count: they're still on, and listed.
    public var isTodayAvailable: Bool
    /// What the list shows: the stored choice, or the week while Today has nothing.
    public var effective: PanelListFilter
    public var sections: [PanelSection]

    /// The heading over everything that hasn't started, under Now.
    public static let upcomingTitle = "Upcoming events"

    /// "Now" or "Also now": meetings in progress besides the card's.
    public var now: PanelSection? { sections.first { $0.kind == .now } }

    /// What goes under "Upcoming events": today's meetings yet to start, then each following day's.
    public var upcoming: [PanelSection] { sections.filter { $0.kind != .now } }

    /// 7 Days heads each day under "Upcoming events" (Today, Tomorrow, Wednesday…), as the user asked.
    /// Today, or a list that is only today, needs no day heading.
    public var showsDayHeadings: Bool { effective == .week && isShown }
}

/// Only one hero card is shown at a time.
public enum PanelHero: Equatable, Sendable {
    /// "No more meetings today", with a line like "Next up tomorrow at 1:00 PM, in 15 h 30 min".
    case nothingToday(detail: String)
    /// A neutral card for the next meeting later today.
    case next(PanelCard)
    /// An accent card for a meeting about to start (within the menu bar pill's window).
    case startingSoon(PanelCard)
    /// The meeting you are in, with its progress.
    case now(PanelCard)

    public var card: PanelCard? {
        switch self {
        case .nothingToday: return nil
        case .next(let card), .startingSoon(let card), .now(let card): return card
        }
    }
}

public struct PanelCard: Equatable, Sendable {
    public var meeting: Meeting
    /// "Next · in 2 h 15 min", "Starts in 4 min", "Now · 40 min left".
    public var label: String
    /// "1:00 – 2:00 PM".
    public var timeRange: String
    /// Short location ("C. de Ruiz de Alarcón, 23 · Retiro") when the meeting has a physical place.
    public var location: String?
    /// "Overlaps Workshop, which runs until 7:30 PM".
    public var overlap: String?
    /// Elapsed fraction, for the card of the meeting you are in.
    public var progress: Double?
    public var action: PanelAction?

    public init(
        meeting: Meeting,
        label: String,
        timeRange: String,
        location: String? = nil,
        overlap: String? = nil,
        progress: Double? = nil,
        action: PanelAction? = nil
    ) {
        self.meeting = meeting
        self.label = label
        self.timeRange = timeRange
        self.location = location
        self.overlap = overlap
        self.progress = progress
        self.action = action
    }
}

public struct PanelSection: Equatable, Identifiable, Sendable {
    /// Now and Today belong to today; each following day's section is later.
    public enum Kind: Equatable, Sendable {
        /// Meetings in progress besides the card's ("Now", "Also now"), dismissed ones included.
        case now
        /// Today's meetings yet to start.
        case today
        case later
    }

    public var id: String
    /// "Now", "Also now", "Today", "Tomorrow", "Wednesday".
    public var title: String
    /// "Wed 7 Oct" after "Tomorrow", "7 Oct" after a weekday.
    public var subtitle: String?
    public var rows: [PanelRow]
    public var kind: Kind

    public init(id: String, title: String, subtitle: String? = nil, rows: [PanelRow], kind: Kind = .today) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.rows = rows
        self.kind = kind
    }
}

public struct PanelRow: Equatable, Identifiable, Sendable {
    public enum Detail: Equatable, Sendable {
        /// Pin + short location.
        case location(String)
        /// Amber warning: "Overlaps Workshop".
        case overlap(String)
        /// For a meeting already running: elapsed fraction and "3 h 10 min left".
        case progress(Double, String)
        /// For a dismissed meeting, in place of the others: "Dismissed", or "Dismissed · 34 min left" once
        /// it's running (`DismissCopy.dismissedDetail`).
        case dismissed(String)
    }

    /// What a row offers besides its action: Dismiss, or Restore once dismissed.
    public enum Dismissal: Equatable, Sendable {
        /// A meeting that may alert: Dismiss takes it off the alert, the menu bar item and the card.
        case dismissable
        /// A dismissed meeting, listed until it ends: Restore brings it back everywhere.
        case dismissed
    }

    public var meeting: Meeting
    public var startTime: String
    public var endTime: String
    public var detail: Detail?
    public var action: PanelAction?
    /// Out-of-office blocks are drawn striped and muted, with no Join or Directions button. Dismissed rows
    /// aren't muted: they're still on, so they count for Today (`PanelContent.filtered(by:)`).
    public var isMuted: Bool
    /// nil for a meeting that never alerts (Show in the list only, out-of-office blocks by default): there's
    /// nothing to dismiss.
    public var dismissal: Dismissal?

    public var id: String { meeting.id }

    public init(
        meeting: Meeting,
        startTime: String,
        endTime: String,
        detail: Detail? = nil,
        action: PanelAction? = nil,
        isMuted: Bool = false,
        dismissal: Dismissal? = nil
    ) {
        self.meeting = meeting
        self.startTime = startTime
        self.endTime = endTime
        self.detail = detail
        self.action = action
        self.isMuted = isMuted
        self.dismissal = dismissal
    }
}

/// The words for dismissing an event from the menu bar panel, with the card's or a row's Dismiss button,
/// for a dismissed row, and for bringing it back.
public enum DismissCopy {
    /// The card's Dismiss button, the rows' accessibility action, and the first word of the Dismiss buttons'
    /// VoiceOver labels.
    public static let dismissTitle = "Dismiss"
    /// A dismissed row's accessibility action, and the first word of its Restore button's label.
    public static let restoreTitle = "Restore"
    /// A dismissed row's detail line, after its crossed-out bell.
    public static let dismissedTitle = "Dismissed"

    /// The help tag on a row's Dismiss button.
    public static let rowDismissHelp = "Dismiss: no full-screen alert, and it leaves the menu bar and the top card. It stays in this list until it ends."
    /// The help tag on the card's Dismiss button.
    public static let cardDismissHelp = "Dismiss: no full-screen alert, and it leaves the menu bar and this card. It stays in the list until it ends."
    /// The help tag on a dismissed row's Restore button.
    public static let restoreHelp = "Restore: its full-screen alert and the menu bar come back."

    /// "Dismissed" for a meeting yet to start, "Dismissed · 34 min left" for one in progress, `left` being
    /// the time left as a running row's progress line words it.
    public static func dismissedDetail(left: String?) -> String {
        guard let left else { return dismissedTitle }
        return "\(dismissedTitle) · \(left)"
    }

    /// "Dismiss Workshop", for the card's and a row's Dismiss buttons.
    public static func dismissAccessibilityLabel(for meeting: Meeting) -> String {
        "\(dismissTitle) \(meeting.title)"
    }

    /// "Restore Workshop", for a dismissed row's Restore button.
    public static func restoreAccessibilityLabel(for meeting: Meeting) -> String {
        "\(restoreTitle) \(meeting.title)"
    }
}

/// Builds the menu bar panel's content from the meetings and the current time.
public enum PanelPresenter {
    /// - Parameters:
    ///   - meetings: the visible meetings (`MeetingFilter.visible`), out-of-office blocks included; they
    ///     fill the lists.
    ///   - alertable: the meetings that may alert (`MeetingFilter.alertable`); only these drive the hero
    ///     card, picked the way the menu bar picks (`MenuBarPresenter.focus`), and only their rows offer
    ///     Dismiss.
    ///   - dismissed: the Show and alert meetings the user dismissed (`MeetingFilter.dismissedIDs`). They
    ///     never take the card (any left in `alertable` are dropped), clash with nothing, and are listed
    ///     until they end, marked dismissed, with Restore.
    ///   - startingSoonWindow: how soon before its start the next meeting gets the starting-soon card,
    ///     the same window as the menu bar pill.
    public static func content(
        meetings: [Meeting],
        alertable: [Meeting],
        dismissed: Set<String> = [],
        now: Date,
        startingSoonWindow: TimeInterval = MenuBarPresenter.startingSoonWindow,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> PanelContent {
        let alertable = alertable.filter { !dismissed.contains($0.id) }
        let builder = Builder(
            meetings: meetings,
            alertableIDs: Set(alertable.map(\.id)),
            dismissed: dismissed,
            now: now,
            calendar: calendar,
            locale: locale
        )
        // The same choice as the menu bar: a Maybe or unanswered meeting in progress steps aside for an accepted one inside it.
        let focused = MenuBarPresenter.focus(alertable, now: now)
        let next = MenuBarPresenter.nextMeeting(in: focused, now: now)
        let current = MenuBarPresenter.currentMeeting(in: focused, now: now)

        let hero: PanelHero
        if let next, next.start.timeIntervalSince(now) <= startingSoonWindow {
            hero = .startingSoon(builder.card(for: next, label: "Starts in \(MenuBarPresenter.duration(next.start.timeIntervalSince(now)))"))
        } else if let current {
            let left = MenuBarPresenter.duration(current.end.timeIntervalSince(now))
            hero = .now(builder.card(for: current, label: "Now · \(left) left", isOngoing: true))
        } else if let next, calendar.isDate(next.start, inSameDayAs: now) {
            hero = .next(builder.card(for: next, label: "Next · in \(MenuBarPresenter.duration(next.start.timeIntervalSince(now)))"))
        } else {
            hero = .nothingToday(detail: builder.nextUpDetail(next))
        }

        let listed = builder.sorted.filter { !$0.hasEnded(at: now) }
        var sections: [PanelSection] = []

        // The meeting you are in has the card, so Now lists the others, dismissed ones included (they never
        // take the card). Meetings yet to start are all listed, the card's included, so Today reads as the
        // rest of the day (the user's choice); a dismissed one keeps its place there.
        let heroID = hero.card?.meeting.id
        let ongoing = listed.filter { $0.isOngoing(at: now) && $0.id != heroID }
        if !ongoing.isEmpty {
            let title: String
            if case .now = hero { title = "Also now" } else { title = "Now" }
            sections.append(PanelSection(id: "now", title: title, rows: ongoing.map(builder.row), kind: .now))
        }

        let upcoming = listed.filter { $0.isUpcoming(at: now) }
        let today = upcoming.filter { calendar.isDate($0.start, inSameDayAs: now) }
        if !today.isEmpty {
            sections.append(PanelSection(id: "today", title: "Today", rows: today.map(builder.row)))
        }

        var days: [(day: Date, meetings: [Meeting])] = []
        for meeting in upcoming where !calendar.isDate(meeting.start, inSameDayAs: now) {
            let day = calendar.startOfDay(for: meeting.start)
            if days.last?.day == day {
                days[days.count - 1].meetings.append(meeting)
            } else {
                days.append((day, [meeting]))
            }
        }
        for (day, meetings) in days {
            let heading = builder.dayHeading(for: day)
            sections.append(PanelSection(
                id: "day-\(Int(day.timeIntervalSince1970))",
                title: heading.title,
                subtitle: heading.subtitle,
                rows: meetings.map(builder.row),
                kind: .later
            ))
        }

        return PanelContent(hero: hero, sections: sections)
    }

    /// The meeting that `meeting` starts in the middle of, if any: an earlier-starting meeting still running when it
    /// begins (the latest-ending one when there are several). Only the later of two meetings is flagged, and
    /// out-of-office blocks never count. Dismissed meetings don't either: the panel leaves them out of `meetings`.
    public static func overlap(for meeting: Meeting, in meetings: [Meeting]) -> Meeting? {
        guard !meeting.isOutOfOffice else { return nil }
        let order = sortedMeetings(meetings)
        let position = order.firstIndex { $0.id == meeting.id }
        return order.enumerated()
            .filter { index, other in
                guard other.id != meeting.id, !other.isOutOfOffice, other.end > meeting.start else { return false }
                if other.start != meeting.start { return other.start < meeting.start }
                guard let position else { return false }
                return index < position
            }
            .map(\.element)
            .max { $0.end < $1.end }
    }

    static func sortedMeetings(_ meetings: [Meeting]) -> [Meeting] {
        meetings.sorted { ($0.start, $0.title, $0.id) < ($1.start, $1.title, $1.id) }
    }

    private struct Builder {
        let sorted: [Meeting]
        /// What overlaps are looked for among: everything listed but dismissed meetings, which clash with nothing.
        let clashing: [Meeting]
        let alertableIDs: Set<String>
        let dismissed: Set<String>
        let now: Date
        let calendar: Calendar
        let locale: Locale
        let timeFormatter: DateFormatter

        init(meetings: [Meeting], alertableIDs: Set<String>, dismissed: Set<String>, now: Date, calendar: Calendar, locale: Locale) {
            self.sorted = PanelPresenter.sortedMeetings(meetings)
            self.clashing = sorted.filter { !dismissed.contains($0.id) }
            self.alertableIDs = alertableIDs
            self.dismissed = dismissed
            self.now = now
            self.calendar = calendar
            self.locale = locale
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            self.timeFormatter = formatter
        }

        func time(_ date: Date) -> String {
            timeFormatter.string(from: date)
        }

        func card(for meeting: Meeting, label: String, isOngoing: Bool = false) -> PanelCard {
            var card = PanelCard(
                meeting: meeting,
                label: label,
                timeRange: MeetingTimeFormatter.timeRange(start: meeting.start, end: meeting.end, locale: locale, timeZone: calendar.timeZone),
                action: action(for: meeting)
            )
            if isOngoing {
                card.progress = MenuBarPresenter.elapsedFraction(of: meeting, now: now)
            } else {
                card.location = shortLocation(of: meeting)
                if let other = PanelPresenter.overlap(for: meeting, in: clashing) {
                    card.overlap = "Overlaps \(other.title), which runs until \(time(other.end))"
                }
            }
            return card
        }

        func row(_ meeting: Meeting) -> PanelRow {
            var row = PanelRow(meeting: meeting, startTime: time(meeting.start), endTime: time(meeting.end), isMuted: meeting.isOutOfOffice)
            // Dismiss follows what alerts, so an out-of-office block set to Show and alert can be dismissed
            // (and restored) from its row like any meeting, while staying muted.
            let isDismissed = dismissed.contains(meeting.id)
            if isDismissed {
                row.dismissal = .dismissed
                row.detail = .dismissed(DismissCopy.dismissedDetail(left: meeting.isOngoing(at: now) ? timeLeft(meeting) : nil))
            } else if alertableIDs.contains(meeting.id) {
                row.dismissal = .dismissable
            }
            guard !meeting.isOutOfOffice else { return row }
            // Joining a dismissed meeting is still allowed; its detail stays "Dismissed".
            row.action = action(for: meeting)
            guard !isDismissed else { return row }
            if meeting.isOngoing(at: now) {
                row.detail = .progress(MenuBarPresenter.elapsedFraction(of: meeting, now: now), timeLeft(meeting))
            } else if let other = PanelPresenter.overlap(for: meeting, in: clashing) {
                row.detail = .overlap("Overlaps \(other.title)")
            } else if let location = shortLocation(of: meeting) {
                row.detail = .location(location)
            }
            return row
        }

        /// "3 h 10 min left".
        func timeLeft(_ meeting: Meeting) -> String {
            "\(MenuBarPresenter.duration(meeting.end.timeIntervalSince(now))) left"
        }

        func action(for meeting: Meeting) -> PanelAction? {
            if let url = meeting.joinURL { return .join(url) }
            if let place = LocationFormatter.physicalPlace(in: meeting.location),
               let url = LocationFormatter.directionsURL(to: place) {
                return .directions(url)
            }
            return nil
        }

        func shortLocation(of meeting: Meeting) -> String? {
            LocationFormatter.physicalPlace(in: meeting.location).map(LocationFormatter.shortLocation)
        }

        /// "Next up tomorrow at 1:00 PM, in 15 h 30 min"; the countdown is left out a day or more ahead.
        func nextUpDetail(_ next: Meeting?) -> String {
            guard let next else { return "Nothing in the next 7 days" }
            let day = MenuBarPresenter.relativeDay(next.start, now: now, calendar: calendar, locale: locale)
            let text = "Next up \(day) at \(time(next.start))"
            let until = next.start.timeIntervalSince(now)
            return until < 24 * 60 * 60 ? "\(text), in \(MenuBarPresenter.duration(until))" : text
        }

        /// ("Tomorrow", "Wed 7 Oct") or ("Wednesday", "7 Oct").
        func dayHeading(for day: Date) -> (title: String, subtitle: String) {
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(day, inSameDayAs: tomorrow) {
                return ("Tomorrow", MenuBarPresenter.formatter(template: "EEEdMMM", calendar: calendar, locale: locale).string(from: day))
            }
            let weekday = MenuBarPresenter.formatter(template: "EEEE", calendar: calendar, locale: locale).string(from: day)
            return (
                MenuBarPresenter.capitalizingFirst(weekday),
                MenuBarPresenter.formatter(template: "dMMM", calendar: calendar, locale: locale).string(from: day)
            )
        }
    }
}
