import Foundation

/// Which occurrences of an event Dismiss or Restore acts on. An event that doesn't repeat only has the one;
/// a repeating event's buttons ask, in the words macOS Calendar uses when a repeating event is changed.
public enum DismissScope: CaseIterable, Hashable, Sendable {
    /// This occurrence only.
    case thisEvent
    /// This occurrence and every later one of its series (`Meeting.seriesID`): those beyond the 7-day window
    /// and those not in the calendar yet too, for as long as the rule stands.
    case allFutureEvents
}

/// The events the user dismissed from the menu bar panel: no full-screen alert, and they leave the menu bar
/// item and the panel's card to whatever comes next, while the lists keep them, marked, until they end.
/// `isDismissed(_:)` decides, from three kinds of entry:
///
/// - `occurrences`: occurrences dismissed one by one (any event that doesn't repeat, and This Event on one
///   that does), keyed by `Meeting.id`, so an event moved to another start is a new occurrence that isn't
///   dismissed. Each keeps the occurrence's end, so it can be dropped once the event is over (`pruned`).
/// - `seriesRules`: All Future Events, by series id: every occurrence starting from the one it was chosen on,
///   with no end, or up to the occurrence where Restore All Future Events was chosen later.
/// - `exceptions`: occurrences brought back one by one (Restore This Event) while a rule covers them, so the
///   rest of the series stays dismissed. They go at their occurrence's end, like `occurrences`.
public struct DismissedEvents: Codable, Equatable, Sendable {
    /// An occurrence dismissed, or restored inside a series rule. Its start and series let a series choice find
    /// the entries it covers; an entry saved by 1.2.0 has neither until `pruned` meets its event.
    struct Occurrence: Codable, Equatable, Sendable {
        var start: Date?
        /// When the entry expires.
        var end: Date
        var seriesID: String?

        init(start: Date? = nil, end: Date, seriesID: String? = nil) {
            self.start = start
            self.end = end
            self.seriesID = seriesID
        }

        init(_ meeting: Meeting) {
            self.init(start: meeting.start, end: meeting.end, seriesID: meeting.seriesID)
        }

        /// One of `seriesID`'s occurrences starting at `start` or later.
        func isInSeries(_ seriesID: String, from start: Date) -> Bool {
            guard self.seriesID == seriesID, let ownStart = self.start else { return false }
            return ownStart >= start
        }
    }

    /// A series' occurrences starting at `from` or later, and before `until` when there is one.
    struct SeriesRule: Codable, Equatable, Sendable {
        /// The start of the occurrence All Future Events was chosen on.
        var from: Date
        /// The start of the later occurrence Restore All Future Events was chosen on, if any.
        var until: Date?

        init(from: Date, until: Date? = nil) {
            self.from = from
            self.until = until
        }

        func covers(_ start: Date) -> Bool {
            start >= from && (until.map { start < $0 } ?? true)
        }
    }

    /// Occurrence id → the occurrence dismissed on its own.
    private(set) var occurrences: [String: Occurrence]
    /// Series id → the rules dismissing its occurrences, in order and never overlapping. Usually one; a second
    /// one appears when All Future Events is chosen after a Restore All Future Events further on, so the
    /// occurrences still listed between the two stay dismissed.
    private(set) var seriesRules: [String: [SeriesRule]]
    /// Occurrence id → an occurrence restored on its own inside a series rule.
    private(set) var exceptions: [String: Occurrence]

    /// Nothing dismissed.
    public init() {
        self.init(occurrences: [:])
    }

    init(
        occurrences: [String: Occurrence] = [:],
        seriesRules: [String: [SeriesRule]] = [:],
        exceptions: [String: Occurrence] = [:]
    ) {
        self.occurrences = occurrences
        self.seriesRules = seriesRules
        self.exceptions = exceptions
    }

    public var isEmpty: Bool { occurrences.isEmpty && seriesRules.isEmpty && exceptions.isEmpty }

    /// Without series rules, and without the exceptions that only matter inside one: the occurrences dismissed
    /// one by one stay. A fixture run starts from this (`AppModel`), since its series ids come back every launch.
    public var withoutSeriesRules: DismissedEvents { DismissedEvents(occurrences: occurrences) }

    /// Whether `meeting` is dismissed: on its own, or by a rule of its series that it wasn't restored from.
    public func isDismissed(_ meeting: Meeting) -> Bool {
        if occurrences[meeting.id] != nil { return true }
        return exceptions[meeting.id] == nil && isCoveredBySeriesRule(meeting)
    }

    /// Whether `meeting` is dismissed by a rule of its series (Dismiss All Future Events), so its Restore asks
    /// This Event or All Future Events. One dismissed on its own restores at once, with nothing to ask (the
    /// user's ask, 2026-10-15), even when it repeats.
    public func isDismissedBySeries(_ meeting: Meeting) -> Bool {
        exceptions[meeting.id] == nil && isCoveredBySeriesRule(meeting)
    }

    /// Whether a rule of `meeting`'s series covers it, exceptions aside.
    func isCoveredBySeriesRule(_ meeting: Meeting) -> Bool {
        guard let seriesID = meeting.seriesID, let rules = seriesRules[seriesID] else { return false }
        return rules.contains { $0.covers(meeting.start) }
    }

    /// With `meeting` dismissed, and with All Future Events, every later occurrence of its series too. For an
    /// event that doesn't repeat, All Future Events is This Event.
    public func dismissing(_ meeting: Meeting, scope: DismissScope = .thisEvent) -> DismissedEvents {
        var copy = self
        guard scope == .allFutureEvents, let seriesID = meeting.seriesID else {
            if isCoveredBySeriesRule(meeting) {
                // Already dismissed by its series, unless it was restored on its own: then the rule covers it again.
                copy.exceptions[meeting.id] = nil
            } else {
                copy.occurrences[meeting.id] = Occurrence(meeting)
            }
            return copy
        }
        let start = meeting.start
        // Rules starting here or later are covered by this one. A rule from earlier that reaches this occurrence,
        // or stops right at it, now runs on with no end; any other ends before it and stays.
        var rules = (seriesRules[seriesID] ?? []).filter { $0.from < start }
        if let reaching = rules.firstIndex(where: { rule in rule.until.map { $0 >= start } ?? true }) {
            rules[reaching].until = nil
        } else {
            rules.append(SeriesRule(from: start))
        }
        copy.seriesRules[seriesID] = rules
        // Entries from here on are the rule's now: dismissed ones are covered, restored ones dismissed again.
        copy.occurrences = occurrences.filter { id, entry in id != meeting.id && !entry.isInSeries(seriesID, from: start) }
        copy.exceptions = exceptions.filter { id, entry in id != meeting.id && !entry.isInSeries(seriesID, from: start) }
        return copy
    }

    /// With `meeting` back to normal (its alert, if still due, the menu bar and the card), and with All Future
    /// Events, every later occurrence of its series too, however they were dismissed. Earlier occurrences stay
    /// as they are. This Event inside a series rule makes an exception, so the rest of the series stays dismissed.
    public func restoring(_ meeting: Meeting, scope: DismissScope = .thisEvent) -> DismissedEvents {
        var copy = self
        copy.occurrences[meeting.id] = nil
        guard scope == .allFutureEvents, let seriesID = meeting.seriesID else {
            if isCoveredBySeriesRule(meeting) {
                copy.exceptions[meeting.id] = Occurrence(meeting)
            }
            return copy
        }
        let start = meeting.start
        if let rules = seriesRules[seriesID] {
            // Rules starting here or later go; one from earlier stops at this occurrence.
            let kept = rules.filter { $0.from < start }.map { rule in
                var rule = rule
                if rule.until.map({ $0 > start }) ?? true { rule.until = start }
                return rule
            }
            copy.seriesRules[seriesID] = kept.isEmpty ? nil : kept
        }
        copy.occurrences = copy.occurrences.filter { _, entry in !entry.isInSeries(seriesID, from: start) }
        // No rule covers this occurrence or later ones any more, so their exceptions mean nothing.
        copy.exceptions = exceptions.filter { id, entry in id != meeting.id && !entry.isInSeries(seriesID, from: start) }
        return copy
    }

    /// Without the entries whose events are over, and without rules that can't cover anything listed again.
    ///
    /// An occurrence among `meetings` is over at its end there, which replaces the stored one: an event
    /// extended after it was dismissed must not come back at its old end. Its start and series are taken from
    /// there too, which completes entries saved by 1.2.0. One that isn't among them (its calendar unchecked, a
    /// fetch that failed) is kept until its stored end. A series rule with no end never expires: it covers
    /// occurrences not in the calendar yet. One that stops at a later occurrence goes once that start has passed
    /// and none of its occurrences among `meetings` is still running. An exception goes with its rule.
    public func pruned(at now: Date, meetings: [Meeting]) -> DismissedEvents {
        let current = Dictionary(meetings.map { ($0.id, $0) }, uniquingKeysWith: { $0.end >= $1.end ? $0 : $1 })
        func unended(_ entries: [String: Occurrence]) -> [String: Occurrence] {
            var kept: [String: Occurrence] = [:]
            for (id, stored) in entries {
                let entry = current[id].map(Occurrence.init) ?? stored
                if entry.end > now { kept[id] = entry }
            }
            return kept
        }

        var copy = DismissedEvents()
        copy.occurrences = unended(occurrences)
        for (seriesID, rules) in seriesRules {
            let kept = rules.filter { rule in
                guard let until = rule.until, until <= now else { return true }
                return meetings.contains { $0.seriesID == seriesID && rule.covers($0.start) && $0.end > now }
            }
            if !kept.isEmpty { copy.seriesRules[seriesID] = kept }
        }
        copy.exceptions = unended(exceptions).filter { _, entry in
            guard let seriesID = entry.seriesID, let start = entry.start, let rules = copy.seriesRules[seriesID] else { return false }
            return rules.contains { $0.covers(start) }
        }
        return copy
    }

    // Stored as JSON: {"occurrences": {id: {"start", "end", "seriesID"}}, "seriesRules": {series id: [{"from",
    // "until"}]}, "exceptions": {id: {…}}}. 1.2.0 stored a plain object of occurrence id → end, which still reads,
    // as occurrences dismissed one by one.

    private enum CodingKeys: String, CodingKey {
        case occurrences
        case seriesRules
        case exceptions
    }

    public init(from decoder: Decoder) throws {
        if let ends = try? decoder.singleValueContainer().decode([String: Date].self) {
            self.init(occurrences: ends.mapValues { Occurrence(end: $0) })
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                occurrences: try container.decode([String: Occurrence].self, forKey: .occurrences),
                seriesRules: try container.decode([String: [SeriesRule]].self, forKey: .seriesRules),
                exceptions: try container.decode([String: Occurrence].self, forKey: .exceptions)
            )
        }
    }
}
