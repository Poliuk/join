import Foundation

/// What a meeting's button in the menu bar panel does.
public enum PanelAction: Hashable, Sendable {
    case join(URL)
    case directions(URL)
}

/// The menu bar panel below its header: one hero card, then sections of rows. Built by `PanelPresenter` only,
/// like the cards, sections and rows in it, so the rules that keep their parts consistent stay in one place:
/// the app reads them.
public struct PanelContent: Equatable, Sendable {
    public let hero: PanelHero
    public let sections: [PanelSection]

    init(hero: PanelHero, sections: [PanelSection]) {
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
    public let isShown: Bool
    /// False when nothing is left today but out-of-office blocks (evenings, the day's last meeting): Today
    /// is dimmed and the week shows, so Today never leads to an empty list. The stored choice is kept, so
    /// Today comes back by itself the next morning. Dismissed events count: they're still on, and listed.
    public let isTodayAvailable: Bool
    /// What the list shows: the stored choice, or the week while Today has nothing.
    public let effective: PanelListFilter
    public let sections: [PanelSection]

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
    /// What the card shows under its time range: one or the other, so a card can't have both a progress bar
    /// and a place or an overlap warning.
    public enum Detail: Equatable, Sendable {
        /// The meeting you are in: its elapsed fraction, drawn as a progress bar.
        case ongoing(progress: Double)
        /// A meeting yet to start: its short location ("C. de Ruiz de Alarcón, 23 · Retiro") when it has a
        /// physical place, and what it overlaps ("Overlaps Workshop, which runs until 7:30 PM").
        case upcoming(location: String?, overlap: String?)
    }

    public let meeting: Meeting
    /// "Next · in 2 h 15 min", "Starts in 4 min", "Now · 40 min left".
    public let label: String
    /// "1:00 – 2:00 PM".
    public let timeRange: String
    public let detail: Detail
    public let action: PanelAction?

    init(meeting: Meeting, label: String, timeRange: String, detail: Detail, action: PanelAction? = nil) {
        self.meeting = meeting
        self.label = label
        self.timeRange = timeRange
        self.detail = detail
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

    public let id: String
    /// "Now", "Also now", "Today", "Tomorrow", "Wednesday".
    public let title: String
    /// "Wed 7 Oct" after "Tomorrow", "7 Oct" after a weekday.
    public let subtitle: String?
    public let rows: [PanelRow]
    public let kind: Kind

    init(id: String, title: String, subtitle: String? = nil, rows: [PanelRow], kind: Kind = .today) {
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

    /// What a row offers besides its action: Dismiss, or Restore once dismissed. `asksScope` when its button
    /// opens This Event / All Future Events instead of acting at once: Dismiss on a repeating event; Restore only
    /// on one dismissed with its series (Dismiss All Future Events). A repeating event dismissed on its own
    /// restores at once, that occurrence only, even when others of its series are dismissed (the user's ask,
    /// 2026-10-15). Kept in the case, so a row with nothing to dismiss has no choice to ask about. The card's
    /// Dismiss is a `dismissable(for:)` too, so the views never decide for themselves whether a button asks.
    public enum Dismissal: Equatable, Sendable {
        /// A meeting that may alert: Dismiss takes it off the alert, the menu bar item and the card.
        case dismissable(asksScope: Bool)
        /// A dismissed meeting, listed until it ends: Restore brings it back everywhere.
        case dismissed(asksScope: Bool)

        /// Dismiss for `meeting`: asks This Event or All Future Events when it repeats.
        public static func dismissable(for meeting: Meeting) -> Dismissal {
            .dismissable(asksScope: meeting.isRepeating)
        }

        public var isDismissed: Bool {
            if case .dismissed = self { return true }
            return false
        }

        public var asksScope: Bool {
            switch self {
            case .dismissable(let asks), .dismissed(let asks): return asks
            }
        }
    }

    public let meeting: Meeting
    public let startTime: String
    public let endTime: String
    public internal(set) var detail: Detail?
    public internal(set) var action: PanelAction?
    /// nil for a meeting that never alerts (Show in the list only, out-of-office blocks by default): there's
    /// nothing to dismiss.
    public internal(set) var dismissal: Dismissal?

    public var id: String { meeting.id }

    /// Out-of-office blocks are drawn striped and muted, with no Join or Directions button: the meeting
    /// decides, so a row can't be muted while its meeting isn't out of office. Dismissed rows aren't muted:
    /// they're still on, so they count for Today (`PanelContent.filtered(by:)`).
    public var isMuted: Bool { meeting.isOutOfOffice }

    init(meeting: Meeting, startTime: String, endTime: String) {
        self.meeting = meeting
        self.startTime = startTime
        self.endTime = endTime
    }
}

/// The words for dismissing an event from the menu bar panel, with the card's or a row's Dismiss button,
/// for a dismissed row, and for bringing it back. When a button asks (`PanelRow.Dismissal.asksScope`), it
/// opens a menu whose choices are worded the way macOS Calendar asks about a repeating event: This Event or
/// All Future Events. The help tags and labels take that same `asksScope`, so they say a menu opens exactly
/// when one does. "Alerts" covers both kinds: a dismissed event gets no full-screen alert and no notification,
/// and one already delivered is withdrawn (`NotificationSchedule.withdrawals`).
public enum DismissCopy {
    /// The card's Dismiss button, a row's accessibility action when Dismiss doesn't ask, and the first word of
    /// the Dismiss buttons' VoiceOver labels.
    public static let dismissTitle = "Dismiss"
    /// A dismissed row's accessibility action when Restore doesn't ask, and the first word of its Restore
    /// button's label.
    public static let restoreTitle = "Restore"
    /// A dismissed row's detail line, after its crossed-out bell.
    public static let dismissedTitle = "Dismissed"

    /// The base of a row's Dismiss help tag; `rowDismissHelp(asksScope:)` adds `repeatingNote` when it asks.
    private static let rowDismissBase = "Dismiss: no alerts, and it leaves the menu bar and the top card. It stays in this list until it ends."
    /// The base of the card's Dismiss help tag; `cardDismissHelp(asksScope:)` adds `repeatingNote` when it asks.
    private static let cardDismissBase = "Dismiss: no alerts, and it leaves the menu bar and this card. It stays in the list until it ends."
    /// The base of a dismissed row's Restore help tag; `restoreHelp(asksScope:)` adds `repeatingNote` when it asks.
    private static let restoreBase = "Restore: its alerts and the menu bar come back."
    /// What the help tags add when the button opens a This Event / All Future Events menu (`Dismissal.asksScope`).
    private static let repeatingNote = "It repeats: the menu offers this event or all future events."

    /// The help tag on a row's Dismiss button: with the menu's note when it asks (`Dismissal.asksScope`, a
    /// repeating event).
    public static func rowDismissHelp(asksScope: Bool) -> String {
        help(rowDismissBase, asksScope: asksScope)
    }

    /// The help tag on the card's Dismiss button: with the menu's note when it asks (`Dismissal.asksScope`, a
    /// repeating event).
    public static func cardDismissHelp(asksScope: Bool) -> String {
        help(cardDismissBase, asksScope: asksScope)
    }

    /// The help tag on a dismissed row's Restore button: with the menu's note when it asks (`Dismissal.asksScope`,
    /// an occurrence dismissed with its series), without it for one dismissed on its own.
    public static func restoreHelp(asksScope: Bool) -> String {
        help(restoreBase, asksScope: asksScope)
    }

    private static func help(_ base: String, asksScope: Bool) -> String {
        asksScope ? "\(base) \(repeatingNote)" : base
    }

    /// The Dismiss menu items of a repeating event, and its card's and row's accessibility actions:
    /// "Dismiss This Event", "Dismiss All Future Events".
    public static func dismissChoice(_ scope: DismissScope) -> String {
        switch scope {
        case .thisEvent: return "\(dismissTitle) This Event"
        case .allFutureEvents: return "\(dismissTitle) All Future Events"
        }
    }

    /// The Restore menu items of an occurrence dismissed with its series, and its row's accessibility actions:
    /// "Restore This Event", "Restore All Future Events".
    public static func restoreChoice(_ scope: DismissScope) -> String {
        switch scope {
        case .thisEvent: return "\(restoreTitle) This Event"
        case .allFutureEvents: return "\(restoreTitle) All Future Events"
        }
    }

    /// "Dismissed" for a meeting yet to start, "Dismissed · 34 min left" for one in progress, `left` being
    /// the time left as a running row's progress line words it.
    public static func dismissedDetail(left: String?) -> String {
        guard let left else { return dismissedTitle }
        return "\(dismissedTitle) · \(left)"
    }

    /// "Dismiss Workshop", for the card's and a row's Dismiss buttons; "Dismiss Workshop, opens a menu" when it
    /// asks (`Dismissal.asksScope`, a repeating event).
    public static func dismissAccessibilityLabel(for meeting: Meeting, asksScope: Bool) -> String {
        accessibilityLabel("\(dismissTitle) \(meeting.title)", asksScope: asksScope)
    }

    /// "Restore Workshop", for a dismissed row's Restore button; "Restore Workshop, opens a menu" when it asks
    /// (`Dismissal.asksScope`, an occurrence dismissed with its series).
    public static func restoreAccessibilityLabel(for meeting: Meeting, asksScope: Bool) -> String {
        accessibilityLabel("\(restoreTitle) \(meeting.title)", asksScope: asksScope)
    }

    private static func accessibilityLabel(_ label: String, asksScope: Bool) -> String {
        asksScope ? "\(label), opens a menu" : label
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
    ///   - dismissed: the Show and alert meetings the user dismissed, with how each was dismissed
    ///     (`MeetingFilter.dismissals`). They never take the card (any left in `alertable` are dropped),
    ///     clash with nothing, and are listed until they end, marked dismissed, with Restore, which asks This
    ///     Event or All Future Events for one dismissed with its series (`.allFutureEvents`). A repeating
    ///     event's next occurrence is its own row: it takes the card unless it's dismissed too.
    ///   - startingSoonWindow: how soon before its start the next meeting gets the starting-soon card,
    ///     the same window as the menu bar pill.
    public static func content(
        meetings: [Meeting],
        alertable: [Meeting],
        dismissed: [Meeting.ID: DismissScope] = [:],
        now: Date,
        startingSoonWindow: TimeInterval = MenuBarPresenter.startingSoonWindow,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> PanelContent {
        let alertable = alertable.filter { dismissed[$0.id] == nil }
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
        let dismissed: [Meeting.ID: DismissScope]
        let now: Date
        let calendar: Calendar
        let locale: Locale
        let timeFormatter: DateFormatter

        init(
            meetings: [Meeting],
            alertableIDs: Set<String>,
            dismissed: [Meeting.ID: DismissScope],
            now: Date,
            calendar: Calendar,
            locale: Locale
        ) {
            self.sorted = PanelPresenter.sortedMeetings(meetings)
            self.clashing = sorted.filter { dismissed[$0.id] == nil }
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
            let detail: PanelCard.Detail = if isOngoing {
                .ongoing(progress: MenuBarPresenter.elapsedFraction(of: meeting, now: now))
            } else {
                .upcoming(
                    location: shortLocation(of: meeting),
                    overlap: PanelPresenter.overlap(for: meeting, in: clashing).map { "Overlaps \($0.title), which runs until \(time($0.end))" }
                )
            }
            return PanelCard(
                meeting: meeting,
                label: label,
                timeRange: MeetingTimeFormatter.timeRange(start: meeting.start, end: meeting.end, locale: locale, timeZone: calendar.timeZone),
                detail: detail,
                action: action(for: meeting)
            )
        }

        func row(_ meeting: Meeting) -> PanelRow {
            var row = PanelRow(meeting: meeting, startTime: time(meeting.start), endTime: time(meeting.end))
            // Dismiss follows what alerts, so an out-of-office block set to Show and alert can be dismissed
            // (and restored) from its row like any meeting, while staying muted.
            let scope = dismissed[meeting.id]
            let isDismissed = scope != nil
            if let scope {
                row.dismissal = .dismissed(asksScope: scope == .allFutureEvents)
                row.detail = .dismissed(DismissCopy.dismissedDetail(left: meeting.isOngoing(at: now) ? timeLeft(meeting) : nil))
            } else if alertableIDs.contains(meeting.id) {
                row.dismissal = .dismissable(for: meeting)
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
