import Observation
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
        XCTAssertTrue(preferences.fullScreenAlertsEnabled)
        XCTAssertEqual(preferences.snoozeDurations, [60, 300])
        XCTAssertEqual(preferences.alertScreens, .all)
        XCTAssertEqual(preferences.menuBarDisplay, .time)
        XCTAssertTrue(preferences.autoCloseEnabled)
        XCTAssertNil(preferences.soundName)
        XCTAssertNil(preferences.enabledCalendarIDs)
        XCTAssertEqual(preferences.eventsWithoutParticipants, .showAndAlert)
        XCTAssertEqual(preferences.appearance, .default)
        XCTAssertNil(preferences.customAppearance)
        XCTAssertEqual(preferences.outOfOfficeEvents, .listOnly)
        XCTAssertEqual(preferences.outOfOfficeKeywords, OutOfOfficeDetector.defaultKeywords)
        XCTAssertEqual(preferences.startingSoonPill, .default)
        XCTAssertTrue(preferences.checksForUpdates)
        XCTAssertNil(preferences.lastUpdateCheck)
        XCTAssertNil(preferences.offeredUpdateVersion)
        XCTAssertNil(preferences.unsupportedUpdate)
        XCTAssertTrue(preferences.dismissedEvents.isEmpty)
    }

    @MainActor
    func testValuesPersistAcrossInstances() {
        let pill = StartingSoonPill(minutes: 10, fill: RGBA(rgb: 0xFFD60A), text: .black)
        let first = Preferences(defaults: defaults)
        first.leadTime = 300
        first.soundName = "Glass"
        first.appearance.blurMode = .none
        first.fullScreenAlertsEnabled = false
        first.eventsWithoutParticipants = .listOnly
        first.outOfOfficeEvents = .exclude
        first.startingSoonPill = pill

        let second = Preferences(defaults: defaults)
        XCTAssertEqual(second.leadTime, 300)
        XCTAssertEqual(second.soundName, "Glass")
        XCTAssertEqual(second.appearance.blurMode, .none)
        XCTAssertFalse(second.fullScreenAlertsEnabled)
        XCTAssertEqual(second.eventsWithoutParticipants, .listOnly)
        XCTAssertEqual(second.outOfOfficeEvents, .exclude)
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
    func testEventsChoicesAreStoredAsRawValues() {
        let preferences = Preferences(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: Preferences.Keys.eventsWithoutParticipants), "nothing is stored until it changes")
        XCTAssertNil(defaults.object(forKey: Preferences.Keys.outOfOfficeEvents), "nothing is stored until it changes")

        preferences.eventsWithoutParticipants = .exclude
        preferences.outOfOfficeEvents = .showAndAlert
        XCTAssertEqual(defaults.string(forKey: "eventsWithoutParticipants"), "exclude")
        XCTAssertEqual(defaults.string(forKey: "outOfOfficeEvents"), "showAndAlert")
        XCTAssertEqual(Preferences(defaults: defaults).eventsWithoutParticipants, .exclude)
        XCTAssertEqual(Preferences(defaults: defaults).outOfOfficeEvents, .showAndAlert)
    }

    @MainActor
    func testLegacyEventsWithoutParticipantsSwitchIsMigrated() {
        defaults.set(true, forKey: Preferences.Keys.legacyShowsEventsWithoutParticipants)
        XCTAssertEqual(Preferences(defaults: defaults).eventsWithoutParticipants, .showAndAlert)
        defaults.set(false, forKey: Preferences.Keys.legacyShowsEventsWithoutParticipants)
        XCTAssertEqual(Preferences(defaults: defaults).eventsWithoutParticipants, .exclude)
        XCTAssertNotNil(defaults.object(forKey: Preferences.Keys.legacyShowsEventsWithoutParticipants), "reading doesn't remove it")

        let preferences = Preferences(defaults: defaults)
        preferences.eventsWithoutParticipants = .listOnly
        XCTAssertNil(defaults.object(forKey: Preferences.Keys.legacyShowsEventsWithoutParticipants), "a choice replaces the switch")
        XCTAssertEqual(Preferences(defaults: defaults).eventsWithoutParticipants, .listOnly)
    }

    @MainActor
    func testLegacyOutOfOfficeSwitchesAreMigrated() {
        // (alert, list) → choice; alerting wins, so an upgrade keeps every alert the user had.
        let cases: [(Bool, Bool, EventVisibility)] = [
            (true, true, .showAndAlert),
            (false, true, .listOnly),
            (false, false, .exclude),
            (true, false, .showAndAlert),
        ]
        for (alerts, listed, expected) in cases {
            defaults.removePersistentDomain(forName: suite)
            defaults.set(alerts, forKey: Preferences.Keys.legacyAlertForOutOfOffice)
            defaults.set(listed, forKey: Preferences.Keys.legacyShowOutOfOfficeInList)
            XCTAssertEqual(Preferences(defaults: defaults).outOfOfficeEvents, expected, "alert \(alerts), list \(listed)")
        }

        // Only one of the switches stored: the other is at its 1.1 default (alert off, list on).
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: Preferences.Keys.legacyAlertForOutOfOffice)
        XCTAssertEqual(Preferences(defaults: defaults).outOfOfficeEvents, .showAndAlert)
        defaults.removePersistentDomain(forName: suite)
        defaults.set(false, forKey: Preferences.Keys.legacyShowOutOfOfficeInList)
        XCTAssertEqual(Preferences(defaults: defaults).outOfOfficeEvents, .exclude)
    }

    @MainActor
    func testLegacySkipOutOfOfficeIsMigrated() {
        defaults.set(false, forKey: Preferences.Keys.legacySkipOutOfOffice)
        XCTAssertEqual(Preferences(defaults: defaults).outOfOfficeEvents, .showAndAlert)

        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: Preferences.Keys.legacySkipOutOfOffice)
        XCTAssertEqual(Preferences(defaults: defaults).outOfOfficeEvents, .listOnly)
        defaults.set(false, forKey: Preferences.Keys.legacyShowOutOfOfficeInList)
        XCTAssertEqual(Preferences(defaults: defaults).outOfOfficeEvents, .exclude)

        defaults.set(true, forKey: Preferences.Keys.legacyAlertForOutOfOffice)
        XCTAssertEqual(Preferences(defaults: defaults).outOfOfficeEvents, .showAndAlert, "the 1.1 switch wins over the older key")
    }

    @MainActor
    func testAStoredChoiceWinsOverTheLegacySwitchesAndRemovesThem() {
        defaults.set(false, forKey: Preferences.Keys.legacyShowsEventsWithoutParticipants)
        defaults.set(true, forKey: Preferences.Keys.legacyAlertForOutOfOffice)
        defaults.set(true, forKey: Preferences.Keys.legacySkipOutOfOffice)
        defaults.set(false, forKey: Preferences.Keys.legacyShowOutOfOfficeInList)
        defaults.set("listOnly", forKey: Preferences.Keys.eventsWithoutParticipants)
        defaults.set("listOnly", forKey: Preferences.Keys.outOfOfficeEvents)
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.eventsWithoutParticipants, .listOnly)
        XCTAssertEqual(preferences.outOfOfficeEvents, .listOnly)

        preferences.outOfOfficeEvents = .exclude
        XCTAssertNil(defaults.object(forKey: Preferences.Keys.legacyAlertForOutOfOffice))
        XCTAssertNil(defaults.object(forKey: Preferences.Keys.legacyShowOutOfOfficeInList))
        XCTAssertNil(defaults.object(forKey: Preferences.Keys.legacySkipOutOfOffice))
        XCTAssertNotNil(defaults.object(forKey: Preferences.Keys.legacyShowsEventsWithoutParticipants), "each choice clears only its own")
    }

    @MainActor
    func testAnUnknownStoredChoiceFallsBackToTheLegacySwitchesOrTheDefault() {
        defaults.set("hide", forKey: Preferences.Keys.eventsWithoutParticipants)
        defaults.set("hide", forKey: Preferences.Keys.outOfOfficeEvents)
        XCTAssertEqual(Preferences(defaults: defaults).eventsWithoutParticipants, .showAndAlert)
        XCTAssertEqual(Preferences(defaults: defaults).outOfOfficeEvents, .listOnly)

        defaults.set(false, forKey: Preferences.Keys.legacyShowsEventsWithoutParticipants)
        defaults.set(true, forKey: Preferences.Keys.legacyAlertForOutOfOffice)
        XCTAssertEqual(Preferences(defaults: defaults).eventsWithoutParticipants, .exclude)
        XCTAssertEqual(Preferences(defaults: defaults).outOfOfficeEvents, .showAndAlert)
    }

    @MainActor
    func testNeverKeepsTheLeadTimeForWhenAlertsComeBack() {
        let preferences = Preferences(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: Preferences.Keys.fullScreenAlertsEnabled), "nothing is stored until it changes")
        preferences.leadTime = 300
        preferences.fullScreenAlertsEnabled = false
        XCTAssertEqual(defaults.object(forKey: "fullScreenAlertsEnabled") as? Bool, false)

        let reopened = Preferences(defaults: defaults)
        XCTAssertFalse(reopened.fullScreenAlertsEnabled)
        XCTAssertEqual(reopened.leadTime, 300)

        reopened.fullScreenAlertsEnabled = true
        XCTAssertTrue(Preferences(defaults: defaults).fullScreenAlertsEnabled)
    }

    @MainActor
    func testSnoozeDurationsMustHaveTwoEntries() {
        let preferences = Preferences(defaults: defaults)
        preferences.snoozeDurations = [60]
        XCTAssertEqual(preferences.snoozeDurations, [60, 300])
        preferences.snoozeDurations = [120, 600]
        XCTAssertEqual(preferences.snoozeDurations, [120, 600])
    }

    /// Appearance's Restore Defaults puts back the look only: since 1.2.0 snooze, auto-close and the pill
    /// live on other panes, and the Custom card keeps the user's look.
    @MainActor
    func testRestoreDefaultsRestoresTheLookOnly() {
        let preferences = Preferences(defaults: defaults)
        let custom = AlertAppearance(blurMode: .light, join: AlertButtonColors(fill: RGBA(rgb: 0x2563EB)))
        let pill = StartingSoonPill(minutes: 10, fill: RGBA(rgb: 0xFFD60A), text: .black)
        preferences.appearance = custom
        preferences.snoozeDurations = [180, 600]
        preferences.autoCloseAfter = 30 * 60
        preferences.autoCloseEnabled = false
        preferences.startingSoonPill = pill
        preferences.leadTime = 5 * 60
        preferences.fullScreenAlertsEnabled = false
        preferences.soundName = "Glass"
        XCTAssertFalse(preferences.appearance.isDefault)

        preferences.resetAppearance()
        XCTAssertTrue(preferences.appearance.isDefault)

        let reopened = Preferences(defaults: defaults)
        XCTAssertEqual(reopened.appearance, .default)
        XCTAssertTrue(reopened.appearance.isDefault)
        XCTAssertEqual(reopened.customAppearance, custom, "the Custom card keeps the look")
        XCTAssertEqual(reopened.snoozeDurations, [180, 600])
        XCTAssertFalse(reopened.autoCloseEnabled)
        XCTAssertEqual(reopened.autoCloseAfter, 30 * 60)
        XCTAssertEqual(reopened.startingSoonPill, pill)
        XCTAssertEqual(reopened.leadTime, 5 * 60)
        XCTAssertFalse(reopened.fullScreenAlertsEnabled)
        XCTAssertEqual(reopened.soundName, "Glass")
    }

    @MainActor
    func testTheCustomCardKeepsTheLastLookOfTheUsersOwn() {
        let preferences = Preferences(defaults: defaults)
        preferences.applyCustomAppearance()
        XCTAssertEqual(preferences.appearance, .default, "nothing to restore yet")

        preferences.appearance.blurMode = .light
        XCTAssertNil(preferences.customAppearance, "the Light preset isn't a look of one's own")
        preferences.appearance.pick(.swatch(AlertColorRow.joinChoice.swatches[2]), for: .joinButton)
        let blueOnLight = preferences.appearance
        XCTAssertEqual(blueOnLight.style, .custom)
        XCTAssertEqual(preferences.customAppearance, blueOnLight, "editing a color saves it to the Custom card")

        preferences.appearance = AlertAppearancePreset.midnight.appearance
        XCTAssertEqual(preferences.customAppearance, blueOnLight, "a preset click leaves it")
        preferences.applyCustomAppearance()
        XCTAssertEqual(preferences.appearance, blueOnLight, "clicking the card restores it")

        preferences.appearance.pick(.swatch(AlertColorRow.tintChoice.swatches[3]), for: .tint)
        let plum = preferences.appearance
        XCTAssertEqual(preferences.customAppearance, plum)
        XCTAssertEqual(Preferences(defaults: defaults).customAppearance, plum, "persisted")
    }

    /// The user's blue Join on Light blur, saved by 1.1, opens on the Custom card.
    @MainActor
    func testTheCustomCardIsSeededFromAStoredLookOfTheUsersOwn() throws {
        let stored = #"{"version":2,"blurMode":"light","tintStrength":0.35,"join":{"fill":{"red":0.1450980392156863,"green":0.38823529411764707,"blue":0.9215686274509803,"alpha":1},"fillOpacity":1},"dismissAndSnooze":{"fillOpacity":1}}"#
        defaults.set(Data(stored.utf8), forKey: Preferences.Keys.appearance)
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.appearance.style, .custom)
        XCTAssertEqual(preferences.customAppearance, preferences.appearance)
        XCTAssertNotNil(defaults.data(forKey: Preferences.Keys.customAppearance), "saved at once, so a preset click can't lose it")

        preferences.appearance = AlertAppearancePreset.dark.appearance
        XCTAssertEqual(Preferences(defaults: defaults).customAppearance?.join.fill, RGBA(rgb: 0x2563EB))
    }

    /// 1.1's Fill opacity at 97 % on Dark is a look of the user's own, one 8-bit step from Dark's buttons.
    @MainActor
    func testTheCustomCardIsSeededFromAStoredTranslucentAutomaticFill() throws {
        var stored = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AlertAppearance.default)) as? [String: Any] ?? [:]
        stored["version"] = 2
        stored["dismissAndSnooze"] = ["fillOpacity": 0.97]
        defaults.set(try JSONSerialization.data(withJSONObject: stored), forKey: Preferences.Keys.appearance)
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.appearance.style, .custom)
        XCTAssertEqual(preferences.appearance.palette.buttonFill.hexString, "#FFFFFF28")
        XCTAssertEqual(preferences.customAppearance, preferences.appearance)
    }

    @MainActor
    func testNoCustomLookWhileTheStoredLookIsAPreset() throws {
        var oldHighContrast = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(AlertAppearancePreset.earlierDefinitions[0].appearance)
        ) as? [String: Any] ?? [:]
        oldHighContrast["version"] = 2
        defaults.set(try JSONSerialization.data(withJSONObject: oldHighContrast), forKey: Preferences.Keys.appearance)
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.appearance, AlertAppearancePreset.highContrast.appearance)
        XCTAssertNil(preferences.customAppearance)
        XCTAssertNil(defaults.object(forKey: Preferences.Keys.customAppearance))
    }

    @MainActor
    func testAStoredCustomLookThatMatchesAPresetIsIgnored() throws {
        defaults.set(try JSONEncoder().encode(AlertAppearancePreset.light.appearance), forKey: Preferences.Keys.customAppearance)
        XCTAssertNil(Preferences(defaults: defaults).customAppearance)
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
    func testLegacyShowOnAllScreensIsMigrated() {
        defaults.set(false, forKey: Preferences.Keys.legacyShowOnAllScreens)
        XCTAssertEqual(Preferences(defaults: defaults).alertScreens, .main)

        let preferences = Preferences(defaults: defaults)
        preferences.alertScreens = .pointer
        XCTAssertEqual(Preferences(defaults: defaults).alertScreens, .pointer)
        XCTAssertNil(defaults.object(forKey: Preferences.Keys.legacyShowOnAllScreens))
    }

    @MainActor
    func testAlertScreensPersistEveryChoice() {
        for choice in AlertScreens.allCases {
            Preferences(defaults: defaults).alertScreens = choice
            XCTAssertEqual(defaults.string(forKey: Preferences.Keys.alertScreens), choice.rawValue)
            XCTAssertEqual(Preferences(defaults: defaults).alertScreens, choice)
        }
        defaults.set("main", forKey: Preferences.Keys.alertScreens)
        XCTAssertEqual(Preferences(defaults: defaults).alertScreens, .main, "a value stored before 1.2.0")
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

    // MARK: Dismissed events

    @MainActor
    func testDismissedEventsPersistAndNoneRemovesTheKey() {
        let dismissed = DismissedEvents().dismissing(MenuBarFixtures.workshop).dismissing(MenuBarFixtures.review)
        let first = Preferences(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: Preferences.Keys.dismissedEvents), "nothing is stored until something is dismissed")
        first.dismissedEvents = dismissed
        XCTAssertNotNil(defaults.data(forKey: Preferences.Keys.dismissedEvents))

        let second = Preferences(defaults: defaults)
        XCTAssertEqual(second.dismissedEvents, dismissed)

        second.dismissedEvents = dismissed.restoring(MenuBarFixtures.workshop.id)
        XCTAssertEqual(Preferences(defaults: defaults).dismissedEvents.ids, [MenuBarFixtures.review.id])
        second.dismissedEvents = DismissedEvents()
        XCTAssertNil(defaults.object(forKey: Preferences.Keys.dismissedEvents))
        XCTAssertTrue(Preferences(defaults: defaults).dismissedEvents.isEmpty)
    }

    @MainActor
    func testUnreadableDismissedEventsAreNone() {
        defaults.set(Data("not json".utf8), forKey: Preferences.Keys.dismissedEvents)
        XCTAssertTrue(Preferences(defaults: defaults).dismissedEvents.isEmpty)
        defaults.set(Data(#"{"val": "tonight"}"#.utf8), forKey: Preferences.Keys.dismissedEvents)
        XCTAssertTrue(Preferences(defaults: defaults).dismissedEvents.isEmpty)
        defaults.set("val", forKey: Preferences.Keys.dismissedEvents)
        XCTAssertTrue(Preferences(defaults: defaults).dismissedEvents.isEmpty, "not data at all")
    }

    /// Dismissed events aren't a setting: Restore Defaults and the other resets leave them alone.
    @MainActor
    func testResetsLeaveDismissedEventsAlone() {
        let dismissed = DismissedEvents().dismissing(MenuBarFixtures.workshop)
        let preferences = Preferences(defaults: defaults)
        preferences.dismissedEvents = dismissed
        preferences.appearance = AlertAppearance(blurMode: .light, join: AlertButtonColors(fill: RGBA(rgb: 0x2563EB)))
        preferences.outOfOfficeKeywords = ["away"]

        preferences.resetAppearance()
        preferences.resetOutOfOfficeKeywords()
        preferences.applyCustomAppearance()
        XCTAssertEqual(preferences.dismissedEvents, dismissed)
        XCTAssertEqual(Preferences(defaults: defaults).dismissedEvents, dismissed)
    }

    /// The meeting store reads `dismissedEvents` in `alertableMeetings`, so a dismissal reaches the alert,
    /// the menu bar and the card through observation.
    @MainActor
    func testDismissingNotifiesObservers() {
        final class Changes: @unchecked Sendable { var count = 0 }
        let preferences = Preferences(defaults: defaults)
        let changes = Changes()
        withObservationTracking {
            _ = preferences.dismissedEvents
        } onChange: {
            changes.count += 1
        }
        preferences.dismissedEvents = preferences.dismissedEvents.dismissing(MenuBarFixtures.workshop)
        XCTAssertEqual(changes.count, 1)
    }
}
