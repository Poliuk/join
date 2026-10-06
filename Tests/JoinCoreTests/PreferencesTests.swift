import XCTest
@testable import JoinCore

@MainActor
final class PreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "JoinCoreTests.Preferences"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    func testDefaults() {
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.leadTime, 180)
        XCTAssertEqual(preferences.snoozeDurations, [60, 300])
        XCTAssertEqual(preferences.alertScreens, .all)
        XCTAssertFalse(preferences.menuBarShowsEventTitles)
        XCTAssertTrue(preferences.autoCloseEnabled)
        XCTAssertNil(preferences.soundName)
        XCTAssertNil(preferences.enabledCalendarIDs)
        XCTAssertEqual(preferences.appearance, .default)
        XCTAssertFalse(preferences.alertForOutOfOffice)
        XCTAssertTrue(preferences.showOutOfOfficeInList)
        XCTAssertEqual(preferences.outOfOfficeKeywords, OutOfOfficeDetector.defaultKeywords)
        XCTAssertEqual(preferences.startingSoonPill, .default)
    }

    func testStartingSoonPillPersists() {
        let first = Preferences(defaults: defaults)
        first.startingSoonPill = StartingSoonPill(minutes: 10, fill: RGBA(rgb: 0xFFD60A), text: .black)
        XCTAssertEqual(Preferences(defaults: defaults).startingSoonPill, StartingSoonPill(minutes: 10, fill: RGBA(rgb: 0xFFD60A), text: .black))
        defaults.set(Data("not json".utf8), forKey: Preferences.Keys.startingSoonPill)
        XCTAssertEqual(Preferences(defaults: defaults).startingSoonPill, .default, "unreadable data falls back to the default")
    }

    func testValuesPersistAcrossInstances() {
        let first = Preferences(defaults: defaults)
        first.leadTime = 300
        first.soundName = "Glass"
        var appearance = first.appearance
        appearance.blurMode = .none
        first.appearance = appearance

        let second = Preferences(defaults: defaults)
        XCTAssertEqual(second.leadTime, 300)
        XCTAssertEqual(second.soundName, "Glass")
        XCTAssertEqual(second.appearance.blurMode, .none)
    }

    func testCalendarSelectionStartsAsAllThenBecomesExplicit() {
        let preferences = Preferences(defaults: defaults)
        XCTAssertTrue(preferences.isCalendarEnabled("work"))
        preferences.setCalendar("holidays", enabled: false, allCalendarIDs: ["work", "holidays", "personal"])
        XCTAssertEqual(preferences.enabledCalendarIDs, ["work", "personal"])
        XCTAssertFalse(preferences.isCalendarEnabled("holidays"))
        XCTAssertTrue(preferences.isCalendarEnabled("work"))
        XCTAssertEqual(Preferences(defaults: defaults).enabledCalendarIDs, ["work", "personal"])
    }

    func testSnoozeDurationsMustHaveTwoEntries() {
        let preferences = Preferences(defaults: defaults)
        preferences.snoozeDurations = [60]
        XCTAssertEqual(preferences.snoozeDurations, [60, 300])
        preferences.snoozeDurations = [120, 600]
        XCTAssertEqual(preferences.snoozeDurations, [120, 600])
    }

    func testResetAppearance() {
        let preferences = Preferences(defaults: defaults)
        var appearance = preferences.appearance
        appearance.textColor = .black
        preferences.appearance = appearance
        preferences.resetAppearance()
        XCTAssertEqual(preferences.appearance, .default)
    }

    func testLeadTimeIsWholeMinutes() {
        let preferences = Preferences(defaults: defaults)
        preferences.leadTime = 150
        XCTAssertEqual(preferences.leadTime, 180)
        preferences.leadTime = 89
        XCTAssertEqual(preferences.leadTime, 60)
        preferences.leadTime = -60
        XCTAssertEqual(preferences.leadTime, 0)
    }

    func testStoredLeadTimeWithSecondsIsRoundedOnLoad() {
        defaults.set(210.0, forKey: Preferences.Keys.leadTime)
        XCTAssertEqual(Preferences(defaults: defaults).leadTime, 240)
    }

    func testOutOfOfficeAlertsPersist() {
        let preferences = Preferences(defaults: defaults)
        preferences.alertForOutOfOffice = true
        XCTAssertTrue(Preferences(defaults: defaults).alertForOutOfOffice)
    }

    func testLegacySkipOutOfOfficeIsMigrated() {
        defaults.set(false, forKey: Preferences.Keys.legacySkipOutOfOffice)
        XCTAssertTrue(Preferences(defaults: defaults).alertForOutOfOffice)

        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: Preferences.Keys.legacySkipOutOfOffice)
        XCTAssertFalse(Preferences(defaults: defaults).alertForOutOfOffice)
    }

    func testLegacyShowOnAllScreensIsMigrated() {
        defaults.set(false, forKey: Preferences.Keys.legacyShowOnAllScreens)
        XCTAssertEqual(Preferences(defaults: defaults).alertScreens, .main)

        let preferences = Preferences(defaults: defaults)
        preferences.alertScreens = .pointer
        XCTAssertEqual(Preferences(defaults: defaults).alertScreens, .pointer)
        XCTAssertNil(defaults.object(forKey: Preferences.Keys.legacyShowOnAllScreens))
    }

    func testShowOutOfOfficeInListPersists() {
        let preferences = Preferences(defaults: defaults)
        preferences.showOutOfOfficeInList = false
        XCTAssertFalse(Preferences(defaults: defaults).showOutOfOfficeInList)
    }

    func testPanelListFilterDefaultsToTheWeekAndPersists() {
        XCTAssertEqual(Preferences(defaults: defaults).panelListFilter, .week)
        Preferences(defaults: defaults).panelListFilter = .today
        XCTAssertEqual(Preferences(defaults: defaults).panelListFilter, .today)
        defaults.set("everything", forKey: Preferences.Keys.panelListFilter)
        XCTAssertEqual(Preferences(defaults: defaults).panelListFilter, .week, "an unknown value falls back to the default")
    }
}
