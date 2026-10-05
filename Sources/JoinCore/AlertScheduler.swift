import Foundation

public struct AlertPlan: Equatable, Sendable {
    public var fireAt: Date
    public var meetings: [Meeting]

    public init(fireAt: Date, meetings: [Meeting]) {
        self.fireAt = fireAt
        self.meetings = meetings
    }
}

/// Pure scheduling logic: given what we know, what is the next alert and when?
/// No timers, no windows, no clock reads: `now` is always passed in.
public enum AlertScheduler {
    /// Meetings whose fire time falls within this window of the earliest one share a single alert.
    public static let groupingWindow: TimeInterval = 1

    /// A pending meeting that started more than this long ago is not worth alerting for any more
    /// (for example the app was launched in the middle of it).
    public static let lateAlertGrace: TimeInterval = 5 * 60

    public static func nextPlan(
        meetings: [Meeting],
        states: [Meeting.ID: AlertState],
        leadTime: TimeInterval,
        isPaused: Bool,
        now: Date
    ) -> AlertPlan? {
        guard !isPaused else { return nil }

        var candidates: [(fireAt: Date, meeting: Meeting)] = []
        for meeting in meetings where !meeting.hasEnded(at: now) {
            switch states[meeting.id] ?? .pending {
            case .pending:
                guard now < meeting.start.addingTimeInterval(lateAlertGrace) else { continue }
                candidates.append((max(now, meeting.start.addingTimeInterval(-leadTime)), meeting))
            case .snoozed(let until):
                candidates.append((max(now, until), meeting))
            case .showing, .dismissed:
                continue
            }
        }

        guard let earliest = candidates.map(\.fireAt).min() else { return nil }
        let grouped = candidates
            .filter { $0.fireAt.timeIntervalSince(earliest) <= groupingWindow }
            .map(\.meeting)
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
        return AlertPlan(fireAt: earliest, meetings: grouped)
    }
}
