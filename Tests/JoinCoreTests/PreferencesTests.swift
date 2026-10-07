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
        XCTAssertTrue(preferences.showsEventsWithoutParticipants)
        XCTAssertEqual(preferences.appearance, .default)
        XCTAssertFalse(preferences.alertForOutOfOffice)
        XCTAssertTrue(preferences.showOutOfOfficeInList)
        XCTAssertEqual(preferences.outOfOfficeKeywords, OutOfOfficeDetector.defaultKeywords)
        XCTAssertEqual(preferences.startingSoonPill, .default)
        XCTAssertTrue(preferences.checksForUpdates)
        XCTAssertNil(preferences.lastUpdateCheck)
        XCTAssertNil(preferences.offeredUpdateVersion)
        XCTAssertNil(preferences.unsupportedUpdate)
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
    func testShowsEventsWithoutParticipantsDefaultsOnAndPersists() {
        XCTAssertNil(defaults.object(forKey: Preferences.Keys.showsEventsWithoutParticipants), "nothing is stored until it changes")
        XCTAssertTrue(Preferences(defaults: defaults).showsEventsWithoutParticipants)

        Preferences(defaults: defaults).showsEventsWithoutParticipants = false
        XCTAssertEqual(defaults.object(forKey: "showsEventsWithoutParticipants") as? Bool, false)
        let preferences = Preferences(defaults: defaults)
        XCTAssertFalse(preferences.showsEventsWithoutParticipants)

        preferences.showsEventsWithoutParticipants = true
        XCTAssertTrue(Preferences(defaults: defaults).showsEventsWithoutParticipants)
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

    @MainActor
    func testPanelListFilterDefaultsToTheWeekAndPersists() {
        XCTAssertEqual(Preferences(defaults: defaults).panelListFilter, .week)
        Preferences(defaults: defaults).panelListFilter = .today
        XCTAssertEqual(Preferences(defaults: defaults).panelListFilter, .today)
        defaults.set("everything", forKey: Preferences.Keys.panelListFilter)
        XCTAssertEqual(Preferences(defaults: defaults).panelListFilter, .week, "an unknown value falls back to the default")
    }

    @MainActor
    func testUpdateCheckSettingsPersist() {
        let checked = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let first = Preferences(defaults: defaults)
        first.checksForUpdates = false
        first.lastUpdateCheck = checked
        XCTAssertEqual(defaults.object(forKey: Preferences.Keys.checksForUpdates) as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: Preferences.Keys.lastUpdateCheck) as? Date, checked)

        let second = Preferences(defaults: defaults)
        XCTAssertFalse(second.checksForUpdates)
        XCTAssertEqual(second.lastUpdateCheck, checked)

        second.checksForUpdates = true
        second.lastUpdateCheck = nil
        XCTAssertNil(defaults.object(forKey: Preferences.Keys.lastUpdateCheck))
        let third = Preferences(defaults: defaults)
        XCTAssertTrue(third.checksForUpdates)
        XCTAssertNil(third.lastUpdateCheck)
    }

    @MainActor
    func testOfferedAndUnsupportedUpdatesPersistAndNilRemovesThem() {
        let unsupported = UnsupportedUpdate(version: "1.2.0", minimumSystem: "15.0")
        let first = Preferences(defaults: defaults)
        first.offeredUpdateVersion = "1.1.0"
        first.unsupportedUpdate = unsupported
        XCTAssertEqual(defaults.string(forKey: Preferences.Keys.offeredUpdateVersion), "1.1.0")
        XCTAssertNotNil(defaults.data(forKey: Preferences.Keys.unsupportedUpdate))

        let second = Preferences(defaults: defaults)
        XCTAssertEqual(second.offeredUpdateVersion, "1.1.0")
        XCTAssertEqual(second.unsupportedUpdate, unsupported)

        second.offeredUpdateVersion = nil
        second.unsupportedUpdate = nil
        XCTAssertNil(defaults.object(forKey: Preferences.Keys.offeredUpdateVersion))
        XCTAssertNil(defaults.object(forKey: Preferences.Keys.unsupportedUpdate))
        let third = Preferences(defaults: defaults)
        XCTAssertNil(third.offeredUpdateVersion)
        XCTAssertNil(third.unsupportedUpdate)
    }

    @MainActor
    func testUnreadableUnsupportedUpdateIsNil() {
        defaults.set(Data("not json".utf8), forKey: Preferences.Keys.unsupportedUpdate)
        XCTAssertNil(Preferences(defaults: defaults).unsupportedUpdate)
        defaults.set(Data(#"{"version": "1.2.0"}"#.utf8), forKey: Preferences.Keys.unsupportedUpdate)
        XCTAssertNil(Preferences(defaults: defaults).unsupportedUpdate, "no minimum system")
    }
}
