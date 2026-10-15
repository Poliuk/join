import Testing
@testable import JoinCore

struct AlertScreensTests {
    /// Show on's pop-up, in order (Secondary after Main, before Pointer, 2026-10-07), with the raw values
    /// Preferences stores for good.
    @Test(arguments: [
        (0, AlertScreens.all, "All screens", "all"),
        (1, .main, "Main screen only", "main"),
        (2, .secondary, "Secondary screen only", "secondary"),
        (3, .pointer, "Screen with the pointer", "pointer"),
    ] as [(Int, AlertScreens, String, String)])
    func showOnChoices(position: Int, _ choice: AlertScreens, displayName: String, rawValue: String) {
        #expect(AlertScreens.allCases.firstIndex(of: choice) == position)
        #expect(choice.displayName == displayName)
        #expect(choice.rawValue == rawValue)
    }

    /// The screens each choice covers, as indices where 0 is the main screen. No screens, no alert; otherwise the
    /// alert never silently vanishes: with one screen, Secondary falls back to the main one, and so does Pointer
    /// when the pointer is on no screen (none, one that has gone, or a bad index).
    @Test(arguments: [
        // No screens, no alert.
        (AlertScreens.all, 0, nil, []), (.main, 0, nil, []), (.secondary, 0, nil, []), (.pointer, 0, nil, []),
        // One screen always gets the alert.
        (.all, 1, 0, [0]), (.main, 1, 0, [0]), (.secondary, 1, 0, [0]), (.pointer, 1, 0, [0]),
        // Two screens. Main is the screen with the menu bar, wherever the pointer is.
        (.all, 2, 0, [0, 1]), (.all, 2, 1, [0, 1]),
        (.main, 2, 0, [0]), (.main, 2, 1, [0]),
        (.secondary, 2, 0, [1]), (.secondary, 2, 1, [1]),
        (.pointer, 2, 0, [0]), (.pointer, 2, 1, [1]),
        // Three screens. Secondary is every screen but the main one.
        (.all, 3, 0, [0, 1, 2]), (.all, 3, 1, [0, 1, 2]), (.all, 3, 2, [0, 1, 2]),
        (.main, 3, 0, [0]), (.main, 3, 1, [0]), (.main, 3, 2, [0]),
        (.secondary, 3, 0, [1, 2]), (.secondary, 3, 1, [1, 2]), (.secondary, 3, 2, [1, 2]),
        (.pointer, 3, 0, [0]), (.pointer, 3, 1, [1]), (.pointer, 3, 2, [2]),
        // The pointer on no screen falls back to the main screen.
        (.pointer, 1, nil, [0]), (.pointer, 1, 1, [0]), (.pointer, 1, -1, [0]),
        (.pointer, 2, nil, [0]), (.pointer, 2, 2, [0]), (.pointer, 2, -1, [0]),
        (.pointer, 3, nil, [0]), (.pointer, 3, 3, [0]), (.pointer, 3, -1, [0]),
    ] as [(AlertScreens, Int, Int?, [Int])])
    func targetIndices(_ choice: AlertScreens, screenCount: Int, pointerScreenIndex: Int?, expected: [Int]) {
        #expect(choice.targetIndices(screenCount: screenCount, pointerScreenIndex: pointerScreenIndex) == expected)
    }
}
