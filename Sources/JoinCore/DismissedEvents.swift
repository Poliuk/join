import Foundation

/// The event occurrences the user dismissed from the menu bar panel: no full-screen alert, and they leave the
/// menu bar item and the panel's card to whatever comes next, while the lists keep them, marked, until they
/// end. Keyed by `Meeting.id`, so a recurring event's other occurrences are untouched, and an event moved to
/// another start is a new occurrence that isn't dismissed. Each entry keeps the occurrence's end, so entries
/// can be dropped once their events are over (`pruned`).
public struct DismissedEvents: Codable, Equatable, Sendable {
    /// Occurrence id → the occurrence's end, the entry's expiry.
    public private(set) var ends: [String: Date]

    public init(ends: [String: Date] = [:]) {
        self.ends = ends
    }

    public var isEmpty: Bool { ends.isEmpty }

    public var ids: Set<String> { Set(ends.keys) }

    public func contains(_ id: String) -> Bool {
        ends[id] != nil
    }

    /// With `meeting` dismissed until its end.
    public func dismissing(_ meeting: Meeting) -> DismissedEvents {
        var copy = self
        copy.ends[meeting.id] = meeting.end
        return copy
    }

    /// With the occurrence `id` back to normal: its alert, if still due, the menu bar and the card.
    public func restoring(_ id: String) -> DismissedEvents {
        var copy = self
        copy.ends[id] = nil
        return copy
    }

    /// Without the entries whose events are over. An event among `meetings` is over at its end there, which
    /// replaces the stored one: an event extended after it was dismissed must not come back at its old end.
    /// One that isn't among them (its calendar unchecked, a fetch that failed) is kept until its stored end.
    public func pruned(at now: Date, meetings: [Meeting]) -> DismissedEvents {
        let current = Dictionary(meetings.map { ($0.id, $0.end) }, uniquingKeysWith: max)
        var copy = DismissedEvents()
        for (id, stored) in ends {
            let end = current[id] ?? stored
            if end > now { copy.ends[id] = end }
        }
        return copy
    }

    // Stored as a plain JSON object of id → end, the same shape as `ends`.

    public init(from decoder: Decoder) throws {
        ends = try decoder.singleValueContainer().decode([String: Date].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(ends)
    }
}
