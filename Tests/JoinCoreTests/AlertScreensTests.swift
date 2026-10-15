import Testing
@testable import JoinCore

struct AlertScreensTests {
    @Test func thePopUpOffersTheChoicesInOrder() {
        #expect(AlertScreens.allCases == [.all, .main, .secondary, .pointer])
        #expect(AlertScreens.allCases.map(\.displayName) == [
            "All screens", "Main screen only", "Secondary screen only", "Screen with the pointer",
        ])
    }

    @Test func rawValuesAreWhatPreferencesStore() {
        #expect(AlertScreens.allCases.map(\.rawValue) == ["all", "main", "secondary", "pointer"])
        #expect(AlertScreens(rawValue: "main") == .main, "values stored by earlier builds still read")
        #expect(AlertScreens(rawValue: "pointer") == .pointer)
    }

    @Test func noScreensNoAlert() {
        for choice in AlertScreens.allCases {
            #expect(choice.targetIndices(screenCount: 0, pointerScreenIndex: nil) == [], "\(choice)")
        }
    }

    @Test func oneScreenAlwaysGetsTheAlert() {
        for choice in AlertScreens.allCases {
            #expect(choice.targetIndices(screenCount: 1, pointerScreenIndex: 0) == [0], "\(choice)")
        }
        #expect(AlertScreens.secondary.targetIndices(screenCount: 1, pointerScreenIndex: 0) == [0],
                "with no secondary screen, the main one")
    }

    @Test func twoScreens() {
        for pointer in [0, 1] {
            #expect(AlertScreens.all.targetIndices(screenCount: 2, pointerScreenIndex: pointer) == [0, 1])
            #expect(AlertScreens.main.targetIndices(screenCount: 2, pointerScreenIndex: pointer) == [0],
                    "the screen with the menu bar, wherever the pointer is")
            #expect(AlertScreens.secondary.targetIndices(screenCount: 2, pointerScreenIndex: pointer) == [1])
            #expect(AlertScreens.pointer.targetIndices(screenCount: 2, pointerScreenIndex: pointer) == [pointer])
        }
    }

    @Test func threeScreens() {
        for pointer in [0, 1, 2] {
            #expect(AlertScreens.all.targetIndices(screenCount: 3, pointerScreenIndex: pointer) == [0, 1, 2])
            #expect(AlertScreens.main.targetIndices(screenCount: 3, pointerScreenIndex: pointer) == [0])
            #expect(AlertScreens.secondary.targetIndices(screenCount: 3, pointerScreenIndex: pointer) == [1, 2],
                    "every screen but the main one")
            #expect(AlertScreens.pointer.targetIndices(screenCount: 3, pointerScreenIndex: pointer) == [pointer])
        }
    }

    @Test func thePointerOnNoScreenFallsBackToTheMainScreen() {
        for count in [1, 2, 3] {
            #expect(AlertScreens.pointer.targetIndices(screenCount: count, pointerScreenIndex: nil) == [0], "\(count) screens")
            #expect(AlertScreens.pointer.targetIndices(screenCount: count, pointerScreenIndex: count) == [0],
                    "a screen that has gone")
            #expect(AlertScreens.pointer.targetIndices(screenCount: count, pointerScreenIndex: -1) == [0])
        }
        #expect(AlertScreens.all.targetIndices(screenCount: 2, pointerScreenIndex: nil) == [0, 1])
        #expect(AlertScreens.main.targetIndices(screenCount: 2, pointerScreenIndex: nil) == [0])
        #expect(AlertScreens.secondary.targetIndices(screenCount: 2, pointerScreenIndex: nil) == [1])
    }
}
