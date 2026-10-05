import Foundation

/// Which displays the full-screen alert covers.
public enum AlertScreens: String, Codable, CaseIterable, Sendable {
    case all
    case main
    case pointer

    public var displayName: String {
        switch self {
        case .all: return "All screens"
        case .main: return "Main screen only"
        case .pointer: return "Screen with the pointer"
        }
    }
}
