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
        let today = sections.filter { $0.kind == .today }
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
    /// Today comes back by itself the next morning.
    public var isTodayAvailable: Bool
    /// What the list shows: the stored choice, or the week while Today has nothing.
    public var effective: PanelListFilter
    public var sections: [PanelSection]
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
    }

    public var meeting: Meeting
    public var startTime: String
    public var endTime: String
    public var detail: Detail?
    public var action: PanelAction?
    /// Out-of-office blocks are drawn striped and muted, with no button.
    public var isMuted: Bool

    public var id: String { meeting.id }

    public init(meeting: Meeting, startTime: String, endTime: String, detail: Detail? = nil, action: PanelAction? = nil, isMuted: Bool = false) {
        self.meeting = meeting
        self.startTime = startTime
        self.endTime = endTime
        self.detail = detail
        self.action = action
        self.isMuted = isMuted
    }
}

/// Builds the menu bar panel's content from the meetings and the current time.
public enum PanelPresenter {
    /// - Parameters:
    ///   - meetings: everything in the store, out-of-office blocks included; they fill the lists.
    ///   - alertable: the meetings that may alert; only these drive the hero card, picked the way the
    ///     menu bar picks (`MenuBarPresenter.focus`).
    ///   - showsOutOfOffice: false leaves out-of-office blocks out of the lists.
    ///   - startingSoonWindow: how soon before its start the next meeting gets the starting-soon card,
    ///     the same window as the menu bar pill.
    public static func content(
        meetings: [Meeting],
        alertable: [Meeting],
        now: Date,
        showsOutOfOffice: Bool = true,
        startingSoonWindow: TimeInterval = MenuBarPresenter.startingSoonWindow,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> PanelContent {
        let builder = Builder(meetings: meetings, now: now, calendar: calendar, locale: locale)
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

        let listed = builder.sorted.filter { meeting in
            !meeting.hasEnded(at: now) && (showsOutOfOffice || !meeting.isOutOfOffice)
        }
        var sections: [PanelSection] = []

        // The meeting you are in has the card, so Now lists the others. Meetings yet to start are all
        // listed, the card's included, so Today reads as the rest of the day (the user's choice).
        let heroID = hero.card?.meeting.id
        let ongoing = listed.filter { $0.isOngoing(at: now) && $0.id != heroID }
        if !ongoing.isEmpty {
            let title: String
            if case .now = hero { title = "Also now" } else { title = "Now" }
            sections.append(PanelSection(id: "now", title: title, rows: ongoing.map(builder.row)))
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
    /// out-of-office blocks never count.
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
        let now: Date
        let calendar: Calendar
        let locale: Locale
        let timeFormatter: DateFormatter

        init(meetings: [Meeting], now: Date, calendar: Calendar, locale: Locale) {
            self.sorted = PanelPresenter.sortedMeetings(meetings)
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
                if let other = PanelPresenter.overlap(for: meeting, in: sorted) {
                    card.overlap = "Overlaps \(other.title), which runs until \(time(other.end))"
                }
            }
            return card
        }

        func row(_ meeting: Meeting) -> PanelRow {
            var row = PanelRow(meeting: meeting, startTime: time(meeting.start), endTime: time(meeting.end), isMuted: meeting.isOutOfOffice)
            guard !meeting.isOutOfOffice else { return row }
            row.action = action(for: meeting)
            if meeting.isOngoing(at: now) {
                let left = MenuBarPresenter.duration(meeting.end.timeIntervalSince(now))
                row.detail = .progress(MenuBarPresenter.elapsedFraction(of: meeting, now: now), "\(left) left")
            } else if let other = PanelPresenter.overlap(for: meeting, in: sorted) {
                row.detail = .overlap("Overlaps \(other.title)")
            } else if let location = shortLocation(of: meeting) {
                row.detail = .location(location)
            }
            return row
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
