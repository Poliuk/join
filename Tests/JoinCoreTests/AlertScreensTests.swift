import XCTest
@testable import JoinCore

final class AlertScreensTests: XCTestCase {
    func testThePopUpOffersTheChoicesInOrder() {
        XCTAssertEqual(AlertScreens.allCases, [.all, .main, .secondary, .pointer])
        XCTAssertEqual(AlertScreens.allCases.map(\.displayName), [
            "All screens", "Main screen only", "Secondary screen only", "Screen with the pointer",
        ])
    }

    func testRawValuesAreWhatPreferencesStore() {
        XCTAssertEqual(AlertScreens.allCases.map(\.rawValue), ["all", "main", "secondary", "pointer"])
        XCTAssertEqual(AlertScreens(rawValue: "main"), .main, "values stored by earlier builds still read")
        XCTAssertEqual(AlertScreens(rawValue: "pointer"), .pointer)
    }

    func testNoScreensNoAlert() {
        for choice in AlertScreens.allCases {
            XCTAssertEqual(choice.targetIndices(screenCount: 0, pointerScreenIndex: nil), [], "\(choice)")
        }
    }

    func testOneScreenAlwaysGetsTheAlert() {
        for choice in AlertScreens.allCases {
            XCTAssertEqual(choice.targetIndices(screenCount: 1, pointerScreenIndex: 0), [0], "\(choice)")
        }
        XCTAssertEqual(AlertScreens.secondary.targetIndices(screenCount: 1, pointerScreenIndex: 0), [0],
                       "with no secondary screen, the main one")
    }

    func testTwoScreens() {
        for pointer in [0, 1] {
            XCTAssertEqual(AlertScreens.all.targetIndices(screenCount: 2, pointerScreenIndex: pointer), [0, 1])
            XCTAssertEqual(AlertScreens.main.targetIndices(screenCount: 2, pointerScreenIndex: pointer), [0],
                           "the screen with the menu bar, wherever the pointer is")
            XCTAssertEqual(AlertScreens.secondary.targetIndices(screenCount: 2, pointerScreenIndex: pointer), [1])
            XCTAssertEqual(AlertScreens.pointer.targetIndices(screenCount: 2, pointerScreenIndex: pointer), [pointer])
        }
    }

    func testThreeScreens() {
        for pointer in [0, 1, 2] {
            XCTAssertEqual(AlertScreens.all.targetIndices(screenCount: 3, pointerScreenIndex: pointer), [0, 1, 2])
            XCTAssertEqual(AlertScreens.main.targetIndices(screenCount: 3, pointerScreenIndex: pointer), [0])
            XCTAssertEqual(AlertScreens.secondary.targetIndices(screenCount: 3, pointerScreenIndex: pointer), [1, 2],
                           "every screen but the main one")
            XCTAssertEqual(AlertScreens.pointer.targetIndices(screenCount: 3, pointerScreenIndex: pointer), [pointer])
        }
    }

    func testThePointerOnNoScreenFallsBackToTheMainScreen() {
        for count in [1, 2, 3] {
            XCTAssertEqual(AlertScreens.pointer.targetIndices(screenCount: count, pointerScreenIndex: nil), [0], "\(count) screens")
            XCTAssertEqual(AlertScreens.pointer.targetIndices(screenCount: count, pointerScreenIndex: count), [0],
                           "a screen that has gone")
            XCTAssertEqual(AlertScreens.pointer.targetIndices(screenCount: count, pointerScreenIndex: -1), [0])
        }
        XCTAssertEqual(AlertScreens.all.targetIndices(screenCount: 2, pointerScreenIndex: nil), [0, 1])
        XCTAssertEqual(AlertScreens.main.targetIndices(screenCount: 2, pointerScreenIndex: nil), [0])
        XCTAssertEqual(AlertScreens.secondary.targetIndices(screenCount: 2, pointerScreenIndex: nil), [1])
    }
}
