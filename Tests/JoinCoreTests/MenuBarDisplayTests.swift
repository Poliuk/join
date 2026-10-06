import XCTest
@testable import JoinCore

final class MenuBarDisplayTests: XCTestCase {
    func testMapsTheTwoStoredPreferences() {
        XCTAssertEqual(MenuBarDisplay(showsNextEvent: false, showsTitles: false), .iconOnly)
        XCTAssertEqual(MenuBarDisplay(showsNextEvent: false, showsTitles: true), .iconOnly)
        XCTAssertEqual(MenuBarDisplay(showsNextEvent: true, showsTitles: false), .time)
        XCTAssertEqual(MenuBarDisplay(showsNextEvent: true, showsTitles: true), .titleAndTime)
    }

    func testTitles() {
        XCTAssertEqual(MenuBarDisplay.allCases.map(\.title), ["Icon only", "Time until next event", "Title and time until next event"])
    }
}
