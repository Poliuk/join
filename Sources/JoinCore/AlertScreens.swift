import Foundation

/// Which displays the full-screen alert covers. The main screen is the one with the menu bar, what
/// macOS calls the main display (`NSScreen.screens.first`); the secondary screens are all the others.
/// Stored as its raw value, so a case keeps its raw value for good.
public enum AlertScreens: String, CaseIterable, Sendable {
    case all
    case main
    /// New in 1.2.0.
    case secondary
    case pointer

    public var displayName: String {
        switch self {
        case .all: return "All screens"
        case .main: return "Main screen only"
        case .secondary: return "Secondary screen only"
        case .pointer: return "Screen with the pointer"
        }
    }

    /// The screens the alert covers, as indices into the connected screens, where 0 is the main screen
    /// (the one with the menu bar) and the rest are secondary. `pointerScreenIndex` is the screen under
    /// the pointer, or nil when it's on none of them. The alert never silently vanishes: with a single
    /// screen, Secondary screen only falls back to the main screen, and so does Screen with the pointer
    /// when the pointer isn't on a screen. No screens, no alert.
    public func targetIndices(screenCount: Int, pointerScreenIndex: Int?) -> [Int] {
        guard screenCount > 0 else { return [] }
        let main = 0
        switch self {
        case .all:
            return Array(0..<screenCount)
        case .main:
            return [main]
        case .secondary:
            return screenCount > 1 ? Array(1..<screenCount) : [main]
        case .pointer:
            guard let pointerScreenIndex, (0..<screenCount).contains(pointerScreenIndex) else { return [main] }
            return [pointerScreenIndex]
        }
    }
}
