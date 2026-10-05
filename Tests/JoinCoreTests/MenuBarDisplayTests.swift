import XCTest
@testable import JoinCore

@MainActor
final class MenuBarDisplayTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "JoinCoreTests.MenuBarDisplay"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    func testMapsTheTwoStoredPreferences() {
        XCTAssertEqual(MenuBarDisplay(showsNextEvent: false, showsTitles: false), .iconOnly)
        XCTAssertEqual(MenuBarDisplay(showsNextEvent: false, showsTitles: true), .iconOnly)
        XCTAssertEqual(MenuBarDisplay(showsNextEvent: true, showsTitles: false), .time)
        XCTAssertEqual(MenuBarDisplay(showsNextEvent: true, showsTitles: true), .titleAndTime)
    }

    func testDefaultIsTime() {
        XCTAssertEqual(Preferences(defaults: defaults).menuBarDisplay, .time)
    }

    func testSettingWritesBothPreferencesAndPersists() {
        let preferences = Preferences(defaults: defaults)
        preferences.menuBarDisplay = .titleAndTime
        XCTAssertTrue(preferences.menuBarShowsNextEvent)
        XCTAssertTrue(preferences.menuBarShowsEventTitles)
        XCTAssertEqual(Preferences(defaults: defaults).menuBarDisplay, .titleAndTime)

        preferences.menuBarDisplay = .iconOnly
        XCTAssertFalse(preferences.menuBarShowsNextEvent)
        XCTAssertEqual(Preferences(defaults: defaults).menuBarDisplay, .iconOnly)

        preferences.menuBarDisplay = .time
        XCTAssertTrue(preferences.menuBarShowsNextEvent)
        XCTAssertFalse(preferences.menuBarShowsEventTitles)
    }

    func testTitles() {
        XCTAssertEqual(MenuBarDisplay.allCases.map(\.title), ["Icon only", "Time until next event", "Title and time until next event"])
    }
}
