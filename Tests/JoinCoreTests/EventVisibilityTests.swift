import XCTest
@testable import JoinCore

final class EventVisibilityTests: XCTestCase {
    func testThePopUpOffersTheChoicesInOrder() {
        XCTAssertEqual(EventVisibility.allCases, [.showAndAlert, .listOnly, .exclude])
        XCTAssertEqual(EventVisibility.allCases.map(\.title), ["Show and alert", "Show in the list only", "Exclude"])
    }

    func testRawValuesAreWhatPreferencesStore() {
        XCTAssertEqual(EventVisibility.allCases.map(\.rawValue), ["showAndAlert", "listOnly", "exclude"])
    }

    func testOrderedByHowMuchItShows() {
        XCTAssertLessThan(EventVisibility.exclude, .listOnly)
        XCTAssertLessThan(EventVisibility.listOnly, .showAndAlert)
        XCTAssertEqual(min(EventVisibility.showAndAlert, .listOnly), .listOnly)
        XCTAssertEqual(min(EventVisibility.exclude, .showAndAlert), .exclude)
    }

    func testWhatEachChoiceAllows() {
        XCTAssertTrue(EventVisibility.showAndAlert.isListed)
        XCTAssertTrue(EventVisibility.showAndAlert.alerts)
        XCTAssertTrue(EventVisibility.listOnly.isListed)
        XCTAssertFalse(EventVisibility.listOnly.alerts)
        XCTAssertFalse(EventVisibility.exclude.isListed)
        XCTAssertFalse(EventVisibility.exclude.alerts)
    }
}
