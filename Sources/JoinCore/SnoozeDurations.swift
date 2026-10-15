import Foundation

/// The full-screen alert's two snooze buttons, in seconds. Two fields rather than an array, so there are
/// always exactly two; stored as the two-element array earlier builds kept (`Preferences.snoozeDurations`).
public struct SnoozeDurations: Equatable, Sendable {
    public var first: TimeInterval
    public var second: TimeInterval

    public init(first: TimeInterval, second: TimeInterval) {
        self.first = first
        self.second = second
    }

    /// From what's stored: nil unless it has exactly two entries.
    init?(_ stored: [TimeInterval]) {
        guard stored.count == 2 else { return nil }
        self.init(first: stored[0], second: stored[1])
    }

    /// Both, first button first: what the alert offers and what's stored.
    public var all: [TimeInterval] { [first, second] }
}
