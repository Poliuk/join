import Foundation

/// Whether alerts are paused, and until when.
public enum PauseState: Codable, Hashable, Sendable {
    case active
    case until(Date)
    case indefinitely

    public func isPaused(at now: Date) -> Bool {
        switch self {
        case .active: return false
        case .until(let end): return now < end
        case .indefinitely: return true
        }
    }

    /// An expired timed pause collapses to `.active`.
    public func resolved(at now: Date) -> PauseState {
        if case .until(let end) = self, end <= now { return .active }
        return self
    }

    /// When a timed pause ends, nil otherwise.
    public var endsAt: Date? {
        if case .until(let end) = self { return end }
        return nil
    }
}

/// The pause choices offered by the menu bar panel's bell menu.
public enum PauseOption: String, CaseIterable, Sendable {
    case oneHour
    case untilTomorrow
    case untilResumed

    public var title: String {
        switch self {
        case .oneHour: return "Pause for 1 hour"
        case .untilTomorrow: return "Pause until tomorrow"
        case .untilResumed: return "Pause until I resume"
        }
    }

    public func state(from now: Date, calendar: Calendar = .current) -> PauseState {
        switch self {
        case .oneHour:
            return .until(now.addingTimeInterval(60 * 60))
        case .untilTomorrow:
            let startOfToday = calendar.startOfDay(for: now)
            let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(24 * 60 * 60)
            return .until(startOfTomorrow)
        case .untilResumed:
            return .indefinitely
        }
    }
}
