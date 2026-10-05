import Foundation

/// Where one meeting occurrence is in its alert lifecycle.
public enum AlertState: Codable, Hashable, Sendable {
    case pending
    case snoozed(until: Date)
    case showing
    case dismissed
}
