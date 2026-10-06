import XCTest
@testable import JoinCore

final class PreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "JoinCoreTests.Preferences"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    @MainActor
    func testDefaults() {
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.leadTime, 180)
        XCTAssertEqual(preferences.snoozeDurations, [60, 300])
        XCTAssertEqual(preferences.alertScreens, .all)
        XCTAssertEqual(preferences.menuBarDisplay, .time)
        XCTAssertTrue(preferences.autoCloseEnabled)
        XCTAssertNil(preferences.soundName)
        XCTAssertNil(preferences.enabledCalendarIDs)
        XCTAssertEqual(preferences.appearance, .default)
        XCTAssertFalse(preferences.alertForOutOfOffice)
        XCTAssertTrue(preferences.showOutOfOfficeInList)
        XCTAssertEqual(preferences.outOfOfficeKeywords, OutOfOfficeDetector.defaultKeywords)
        XCTAssertEqual(preferences.startingSoonPill, .default)
    }

    @MainActor
    func testValuesPersistAcrossInstances() {
        let pill = StartingSoonPill(minutes: 10, fill: RGBA(rgb: 0xFFD60A), text: .black)
        let first = Preferences(defaults: defaults)
        first.leadTime = 300
        first.soundName = "Glass"
        first.appearance.blurMode = .none
        first.alertForOutOfOffice = true
        first.showOutOfOfficeInList = false
        first.startingSoonPill = pill

        let second = Preferences(defaults: defaults)
        XCTAssertEqual(second.leadTime, 300)
        XCTAssertEqual(second.soundName, "Glass")
        XCTAssertEqual(second.appearance.blurMode, .none)
        XCTAssertTrue(second.alertForOutOfOffice)
        XCTAssertFalse(second.showOutOfOfficeInList)
        XCTAssertEqual(second.startingSoonPill, pill)
    }

    @MainActor
    func testUnreadableStartingSoonPillFallsBackToDefault() {
        defaults.set(Data("not json".utf8), forKey: Preferences.Keys.startingSoonPill)
        XCTAssertEqual(Preferences(defaults: defaults).startingSoonPill, .default)
    }

    @MainActor
    func testCalendarSelectionStartsAsAllThenBecomesExplicit() {
        let preferences = Preferences(defaults: defaults)
        XCTAssertTrue(preferences.isCalendarEnabled("work"))
        preferences.setCalendar("holidays", enabled: false, allCalendarIDs: ["work", "holidays", "personal"])
        XCTAssertEqual(preferences.enabledCalendarIDs, ["work", "personal"])
        XCTAssertFalse(preferences.isCalendarEnabled("holidays"))
        XCTAssertTrue(preferences.isCalendarEnabled("work"))
        XCTAssertEqual(Preferences(defaults: defaults).enabledCalendarIDs, ["work", "personal"])
    }

    @MainActor
    func testSnoozeDurationsMustHaveTwoEntries() {
        let preferences = Preferences(defaults: defaults)
        preferences.snoozeDurations = [60]
        XCTAssertEqual(preferences.snoozeDurations, [60, 300])
        preferences.snoozeDurations = [120, 600]
        XCTAssertEqual(preferences.snoozeDurations, [120, 600])
    }

    @MainActor
    func testResetAppearance() {
        let preferences = Preferences(defaults: defaults)
        preferences.appearance.textColor = .black
        preferences.resetAppearance()
        XCTAssertEqual(preferences.appearance, .default)
    }

    @MainActor
    func testLeadTimeIsWholeMinutes() {
        let preferences = Preferences(defaults: defaults)
        preferences.leadTime = 150
        XCTAssertEqual(preferences.leadTime, 180)
        preferences.leadTime = 89
        XCTAssertEqual(preferences.leadTime, 60)
        preferences.leadTime = -60
        XCTAssertEqual(preferences.leadTime, 0)
    }

    @MainActor
    func testStoredLeadTimeWithSecondsIsRoundedOnLoad() {
        defaults.set(210.0, forKey: Preferences.Keys.leadTime)
        XCTAssertEqual(Preferences(defaults: defaults).leadTime, 240)
    }

    @MainActor
    func testLegacySkipOutOfOfficeIsMigrated() {
        defaults.set(false, forKey: Preferences.Keys.legacySkipOutOfOffice)
        XCTAssertTrue(Preferences(defaults: defaults).alertForOutOfOffice)

        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: Preferences.Keys.legacySkipOutOfOffice)
        XCTAssertFalse(Preferences(defaults: defaults).alertForOutOfOffice)
    }

    @MainActor
    func testLegacyShowOnAllScreensIsMigrated() {
        defaults.set(false, forKey: Preferences.Keys.legacyShowOnAllScreens)
        XCTAssertEqual(Preferences(defaults: defaults).alertScreens, .main)

        let preferences = Preferences(defaults: defaults)
        preferences.alertScreens = .pointer
        XCTAssertEqual(Preferences(defaults: defaults).alertScreens, .pointer)
        XCTAssertNil(defaults.object(forKey: Preferences.Keys.legacyShowOnAllScreens))
    }

    @MainActor
    func testMenuBarDisplayWritesBothPreferencesAndPersists() {
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
}
