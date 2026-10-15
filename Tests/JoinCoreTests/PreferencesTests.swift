import Foundation
import Observation
import Testing
@testable import JoinCore

/// A class, not a struct, so `deinit` can remove each test's defaults: every test gets a suite of its own,
/// since Swift Testing runs them in parallel. On the main actor, like `Preferences`.
@MainActor
final class PreferencesTests {
    private let suiteName: String
    private let defaults: UserDefaults

    init() throws {
        // A suite named by an absolute path lives in that file, here in the temporary folder: an emptied suite
        // keeps its file, and every run would otherwise leave one per test in ~/Library/Preferences.
        let suiteName = FileManager.default.temporaryDirectory
            .appending(path: "JoinCoreTests.Preferences.\(UUID().uuidString)")
            .path(percentEncoded: false)
        self.suiteName = suiteName
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    /// Removes the suite through a new handle: a nonisolated `deinit` can't touch the main-actor `defaults`.
    deinit {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    @Test func defaultValues() {
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.leadTime == 180)
        #expect(preferences.fullScreenAlertsEnabled)
        #expect(preferences.snoozeDurations == [60, 300])
        #expect(preferences.alertScreens == .all)
        #expect(preferences.menuBarDisplay == .time)
        #expect(preferences.autoCloseEnabled)
        #expect(preferences.soundName == nil)
        #expect(preferences.enabledCalendarIDs == nil)
        #expect(preferences.eventsWithoutParticipants == .showAndAlert)
        #expect(preferences.appearance == .default)
        #expect(preferences.customAppearance == nil)
        #expect(preferences.outOfOfficeEvents == .listOnly)
        #expect(preferences.outOfOfficeKeywords == OutOfOfficeDetector.defaultKeywords)
        #expect(preferences.startingSoonPill == .default)
        #expect(preferences.checksForUpdates)
        #expect(preferences.lastUpdateCheck == nil)
        #expect(preferences.offeredUpdateVersion == nil)
        #expect(preferences.unsupportedUpdate == nil)
        #expect(preferences.dismissedEvents.isEmpty)
    }

    @Test func valuesPersistAcrossInstances() {
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
        #expect(second.leadTime == 300)
        #expect(second.soundName == "Glass")
        #expect(second.appearance.blurMode == .none)
        #expect(!second.fullScreenAlertsEnabled)
        #expect(second.eventsWithoutParticipants == .listOnly)
        #expect(second.outOfOfficeEvents == .exclude)
        #expect(second.startingSoonPill == pill)
    }

    @Test func unreadableStartingSoonPillFallsBackToDefault() {
        defaults.set(Data("not json".utf8), forKey: Preferences.Keys.startingSoonPill)
        #expect(Preferences(defaults: defaults).startingSoonPill == .default)
    }

    @Test func calendarSelectionStartsAsAllThenBecomesExplicit() {
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.isCalendarEnabled("work"))
        preferences.setCalendar("holidays", enabled: false, allCalendarIDs: ["work", "holidays", "personal"])
        #expect(preferences.enabledCalendarIDs == ["work", "personal"])
        #expect(!preferences.isCalendarEnabled("holidays"))
        #expect(preferences.isCalendarEnabled("work"))
        #expect(Preferences(defaults: defaults).enabledCalendarIDs == ["work", "personal"])
    }

    @Test func eventsChoicesAreStoredAsRawValues() {
        let preferences = Preferences(defaults: defaults)
        #expect(defaults.object(forKey: Preferences.Keys.eventsWithoutParticipants) == nil, "nothing is stored until it changes")
        #expect(defaults.object(forKey: Preferences.Keys.outOfOfficeEvents) == nil, "nothing is stored until it changes")

        preferences.eventsWithoutParticipants = .exclude
        preferences.outOfOfficeEvents = .showAndAlert
        #expect(defaults.string(forKey: "eventsWithoutParticipants") == "exclude")
        #expect(defaults.string(forKey: "outOfOfficeEvents") == "showAndAlert")
        #expect(Preferences(defaults: defaults).eventsWithoutParticipants == .exclude)
        #expect(Preferences(defaults: defaults).outOfOfficeEvents == .showAndAlert)
    }

    @Test func legacyEventsWithoutParticipantsSwitchIsMigrated() {
        defaults.set(true, forKey: Preferences.Keys.legacyShowsEventsWithoutParticipants)
        #expect(Preferences(defaults: defaults).eventsWithoutParticipants == .showAndAlert)
        defaults.set(false, forKey: Preferences.Keys.legacyShowsEventsWithoutParticipants)
        #expect(Preferences(defaults: defaults).eventsWithoutParticipants == .exclude)
        #expect(defaults.object(forKey: Preferences.Keys.legacyShowsEventsWithoutParticipants) != nil, "reading doesn't remove it")

        let preferences = Preferences(defaults: defaults)
        preferences.eventsWithoutParticipants = .listOnly
        #expect(defaults.object(forKey: Preferences.Keys.legacyShowsEventsWithoutParticipants) == nil, "a choice replaces the switch")
        #expect(Preferences(defaults: defaults).eventsWithoutParticipants == .listOnly)
    }

    @Test func legacyOutOfOfficeSwitchesAreMigrated() {
        // (alert, list) → choice; alerting wins, so an upgrade keeps every alert the user had.
        let cases: [(Bool, Bool, EventVisibility)] = [
            (true, true, .showAndAlert),
            (false, true, .listOnly),
            (false, false, .exclude),
            (true, false, .showAndAlert),
        ]
        for (alerts, listed, expected) in cases {
            defaults.removePersistentDomain(forName: suiteName)
            defaults.set(alerts, forKey: Preferences.Keys.legacyAlertForOutOfOffice)
            defaults.set(listed, forKey: Preferences.Keys.legacyShowOutOfOfficeInList)
            #expect(Preferences(defaults: defaults).outOfOfficeEvents == expected, "alert \(alerts), list \(listed)")
        }

        // Only one of the switches stored: the other is at its 1.1 default (alert off, list on).
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: Preferences.Keys.legacyAlertForOutOfOffice)
        #expect(Preferences(defaults: defaults).outOfOfficeEvents == .showAndAlert)
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: Preferences.Keys.legacyShowOutOfOfficeInList)
        #expect(Preferences(defaults: defaults).outOfOfficeEvents == .exclude)
    }

    @Test func legacySkipOutOfOfficeIsMigrated() {
        defaults.set(false, forKey: Preferences.Keys.legacySkipOutOfOffice)
        #expect(Preferences(defaults: defaults).outOfOfficeEvents == .showAndAlert)

        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: Preferences.Keys.legacySkipOutOfOffice)
        #expect(Preferences(defaults: defaults).outOfOfficeEvents == .listOnly)
        defaults.set(false, forKey: Preferences.Keys.legacyShowOutOfOfficeInList)
        #expect(Preferences(defaults: defaults).outOfOfficeEvents == .exclude)

        defaults.set(true, forKey: Preferences.Keys.legacyAlertForOutOfOffice)
        #expect(Preferences(defaults: defaults).outOfOfficeEvents == .showAndAlert, "the 1.1 switch wins over the older key")
    }

    @Test func aStoredChoiceWinsOverTheLegacySwitchesAndRemovesThem() {
        defaults.set(false, forKey: Preferences.Keys.legacyShowsEventsWithoutParticipants)
        defaults.set(true, forKey: Preferences.Keys.legacyAlertForOutOfOffice)
        defaults.set(true, forKey: Preferences.Keys.legacySkipOutOfOffice)
        defaults.set(false, forKey: Preferences.Keys.legacyShowOutOfOfficeInList)
        defaults.set("listOnly", forKey: Preferences.Keys.eventsWithoutParticipants)
        defaults.set("listOnly", forKey: Preferences.Keys.outOfOfficeEvents)
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.eventsWithoutParticipants == .listOnly)
        #expect(preferences.outOfOfficeEvents == .listOnly)

        preferences.outOfOfficeEvents = .exclude
        #expect(defaults.object(forKey: Preferences.Keys.legacyAlertForOutOfOffice) == nil)
        #expect(defaults.object(forKey: Preferences.Keys.legacyShowOutOfOfficeInList) == nil)
        #expect(defaults.object(forKey: Preferences.Keys.legacySkipOutOfOffice) == nil)
        #expect(defaults.object(forKey: Preferences.Keys.legacyShowsEventsWithoutParticipants) != nil, "each choice clears only its own")
    }

    @Test func anUnknownStoredChoiceFallsBackToTheLegacySwitchesOrTheDefault() {
        defaults.set("hide", forKey: Preferences.Keys.eventsWithoutParticipants)
        defaults.set("hide", forKey: Preferences.Keys.outOfOfficeEvents)
        #expect(Preferences(defaults: defaults).eventsWithoutParticipants == .showAndAlert)
        #expect(Preferences(defaults: defaults).outOfOfficeEvents == .listOnly)

        defaults.set(false, forKey: Preferences.Keys.legacyShowsEventsWithoutParticipants)
        defaults.set(true, forKey: Preferences.Keys.legacyAlertForOutOfOffice)
        #expect(Preferences(defaults: defaults).eventsWithoutParticipants == .exclude)
        #expect(Preferences(defaults: defaults).outOfOfficeEvents == .showAndAlert)
    }

    @Test func neverKeepsTheLeadTimeForWhenAlertsComeBack() {
        let preferences = Preferences(defaults: defaults)
        #expect(defaults.object(forKey: Preferences.Keys.fullScreenAlertsEnabled) == nil, "nothing is stored until it changes")
        preferences.leadTime = 300
        preferences.fullScreenAlertsEnabled = false
        #expect((defaults.object(forKey: "fullScreenAlertsEnabled") as? Bool) == false)

        let reopened = Preferences(defaults: defaults)
        #expect(!reopened.fullScreenAlertsEnabled)
        #expect(reopened.leadTime == 300)

        reopened.fullScreenAlertsEnabled = true
        #expect(Preferences(defaults: defaults).fullScreenAlertsEnabled)
    }

    @Test func snoozeDurationsMustHaveTwoEntries() {
        let preferences = Preferences(defaults: defaults)
        preferences.snoozeDurations = [60]
        #expect(preferences.snoozeDurations == [60, 300])
        preferences.snoozeDurations = [120, 600]
        #expect(preferences.snoozeDurations == [120, 600])
    }

    /// Appearance's Restore Defaults puts back the look only: since 1.2.0 snooze, auto-close and the pill
    /// live on other panes, and the Custom card keeps the user's look.
    @Test func restoreDefaultsRestoresTheLookOnly() {
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
        #expect(!preferences.appearance.isDefault)

        preferences.resetAppearance()
        #expect(preferences.appearance.isDefault)

        let reopened = Preferences(defaults: defaults)
        #expect(reopened.appearance == .default)
        #expect(reopened.appearance.isDefault)
        #expect(reopened.customAppearance == custom, "the Custom card keeps the look")
        #expect(reopened.snoozeDurations == [180, 600])
        #expect(!reopened.autoCloseEnabled)
        #expect(reopened.autoCloseAfter == 30 * 60)
        #expect(reopened.startingSoonPill == pill)
        #expect(reopened.leadTime == 5 * 60)
        #expect(!reopened.fullScreenAlertsEnabled)
        #expect(reopened.soundName == "Glass")
    }

    @Test func theCustomCardKeepsTheLastLookOfTheUsersOwn() {
        let preferences = Preferences(defaults: defaults)
        preferences.applyCustomAppearance()
        #expect(preferences.appearance == .default, "nothing to restore yet")

        preferences.appearance.blurMode = .light
        #expect(preferences.customAppearance == nil, "the Light preset isn't a look of one's own")
        preferences.appearance.pick(.swatch(AlertColorRow.joinChoice.swatches[2]), for: .joinButton)
        let blueOnLight = preferences.appearance
        #expect(blueOnLight.style == .custom)
        #expect(preferences.customAppearance == blueOnLight, "editing a color saves it to the Custom card")

        preferences.appearance = AlertAppearancePreset.midnight.appearance
        #expect(preferences.customAppearance == blueOnLight, "a preset click leaves it")
        preferences.applyCustomAppearance()
        #expect(preferences.appearance == blueOnLight, "clicking the card restores it")

        preferences.appearance.pick(.swatch(AlertColorRow.tintChoice.swatches[3]), for: .tint)
        let plum = preferences.appearance
        #expect(preferences.customAppearance == plum)
        #expect(Preferences(defaults: defaults).customAppearance == plum, "persisted")
    }

    /// The user's blue Join on Light blur, saved by 1.1, opens on the Custom card.
    @Test func theCustomCardIsSeededFromAStoredLookOfTheUsersOwn() throws {
        let stored = #"{"version":2,"blurMode":"light","tintStrength":0.35,"join":{"fill":{"red":0.1450980392156863,"green":0.38823529411764707,"blue":0.9215686274509803,"alpha":1},"fillOpacity":1},"dismissAndSnooze":{"fillOpacity":1}}"#
        defaults.set(Data(stored.utf8), forKey: Preferences.Keys.appearance)
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.appearance.style == .custom)
        #expect(preferences.customAppearance == preferences.appearance)
        #expect(defaults.data(forKey: Preferences.Keys.customAppearance) != nil, "saved at once, so a preset click can't lose it")

        preferences.appearance = AlertAppearancePreset.dark.appearance
        #expect(Preferences(defaults: defaults).customAppearance?.join.fill == RGBA(rgb: 0x2563EB))
    }

    /// 1.1's Fill opacity at 97 % on Dark is a look of the user's own, one 8-bit step from Dark's buttons.
    @Test func theCustomCardIsSeededFromAStoredTranslucentAutomaticFill() throws {
        var stored = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AlertAppearance.default)) as? [String: Any] ?? [:]
        stored["version"] = 2
        stored["dismissAndSnooze"] = ["fillOpacity": 0.97]
        defaults.set(try JSONSerialization.data(withJSONObject: stored), forKey: Preferences.Keys.appearance)
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.appearance.style == .custom)
        #expect(preferences.appearance.palette.buttonFill.hexString == "#FFFFFF28")
        #expect(preferences.customAppearance == preferences.appearance)
    }

    @Test func noCustomLookWhileTheStoredLookIsAPreset() throws {
        var oldHighContrast = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(AlertAppearancePreset.earlierDefinitions[0].appearance)
        ) as? [String: Any] ?? [:]
        oldHighContrast["version"] = 2
        defaults.set(try JSONSerialization.data(withJSONObject: oldHighContrast), forKey: Preferences.Keys.appearance)
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.appearance == AlertAppearancePreset.highContrast.appearance)
        #expect(preferences.customAppearance == nil)
        #expect(defaults.object(forKey: Preferences.Keys.customAppearance) == nil)
    }

    @Test func aStoredCustomLookThatMatchesAPresetIsIgnored() throws {
        defaults.set(try JSONEncoder().encode(AlertAppearancePreset.light.appearance), forKey: Preferences.Keys.customAppearance)
        #expect(Preferences(defaults: defaults).customAppearance == nil)
    }

    @Test func leadTimeIsWholeMinutes() {
        let preferences = Preferences(defaults: defaults)
        preferences.leadTime = 150
        #expect(preferences.leadTime == 180)
        preferences.leadTime = 89
        #expect(preferences.leadTime == 60)
        preferences.leadTime = -60
        #expect(preferences.leadTime == 0)
    }

    @Test func storedLeadTimeWithSecondsIsRoundedOnLoad() {
        defaults.set(210.0, forKey: Preferences.Keys.leadTime)
        #expect(Preferences(defaults: defaults).leadTime == 240)
    }

    @Test func legacyShowOnAllScreensIsMigrated() {
        defaults.set(false, forKey: Preferences.Keys.legacyShowOnAllScreens)
        #expect(Preferences(defaults: defaults).alertScreens == .main)

        let preferences = Preferences(defaults: defaults)
        preferences.alertScreens = .pointer
        #expect(Preferences(defaults: defaults).alertScreens == .pointer)
        #expect(defaults.object(forKey: Preferences.Keys.legacyShowOnAllScreens) == nil)
    }

    @Test func alertScreensPersistEveryChoice() {
        for choice in AlertScreens.allCases {
            Preferences(defaults: defaults).alertScreens = choice
            #expect(defaults.string(forKey: Preferences.Keys.alertScreens) == choice.rawValue)
            #expect(Preferences(defaults: defaults).alertScreens == choice)
        }
        defaults.set("main", forKey: Preferences.Keys.alertScreens)
        #expect(Preferences(defaults: defaults).alertScreens == .main, "a value stored before 1.2.0")
    }

    @Test func menuBarDisplayWritesBothPreferencesAndPersists() {
        let preferences = Preferences(defaults: defaults)
        preferences.menuBarDisplay = .titleAndTime
        #expect(preferences.menuBarShowsNextEvent)
        #expect(preferences.menuBarShowsEventTitles)
        #expect(Preferences(defaults: defaults).menuBarDisplay == .titleAndTime)

        preferences.menuBarDisplay = .iconOnly
        #expect(!preferences.menuBarShowsNextEvent)
        #expect(Preferences(defaults: defaults).menuBarDisplay == .iconOnly)

        preferences.menuBarDisplay = .time
        #expect(preferences.menuBarShowsNextEvent)
        #expect(!preferences.menuBarShowsEventTitles)
    }

    @Test func panelListFilterDefaultsToTheWeekAndPersists() {
        #expect(Preferences(defaults: defaults).panelListFilter == .week)
        Preferences(defaults: defaults).panelListFilter = .today
        #expect(Preferences(defaults: defaults).panelListFilter == .today)
        defaults.set("everything", forKey: Preferences.Keys.panelListFilter)
        #expect(Preferences(defaults: defaults).panelListFilter == .week, "an unknown value falls back to the default")
    }

    @Test func updateCheckSettingsPersist() {
        let checked = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let first = Preferences(defaults: defaults)
        first.checksForUpdates = false
        first.lastUpdateCheck = checked
        #expect((defaults.object(forKey: Preferences.Keys.checksForUpdates) as? Bool) == false)
        #expect((defaults.object(forKey: Preferences.Keys.lastUpdateCheck) as? Date) == checked)

        let second = Preferences(defaults: defaults)
        #expect(!second.checksForUpdates)
        #expect(second.lastUpdateCheck == checked)

        second.checksForUpdates = true
        second.lastUpdateCheck = nil
        #expect(defaults.object(forKey: Preferences.Keys.lastUpdateCheck) == nil)
        let third = Preferences(defaults: defaults)
        #expect(third.checksForUpdates)
        #expect(third.lastUpdateCheck == nil)
    }

    @Test func offeredAndUnsupportedUpdatesPersistAndNilRemovesThem() {
        let unsupported = UnsupportedUpdate(version: "1.2.0", minimumSystem: "15.0")
        let first = Preferences(defaults: defaults)
        first.offeredUpdateVersion = "1.1.0"
        first.unsupportedUpdate = unsupported
        #expect(defaults.string(forKey: Preferences.Keys.offeredUpdateVersion) == "1.1.0")
        #expect(defaults.data(forKey: Preferences.Keys.unsupportedUpdate) != nil)

        let second = Preferences(defaults: defaults)
        #expect(second.offeredUpdateVersion == "1.1.0")
        #expect(second.unsupportedUpdate == unsupported)

        second.offeredUpdateVersion = nil
        second.unsupportedUpdate = nil
        #expect(defaults.object(forKey: Preferences.Keys.offeredUpdateVersion) == nil)
        #expect(defaults.object(forKey: Preferences.Keys.unsupportedUpdate) == nil)
        let third = Preferences(defaults: defaults)
        #expect(third.offeredUpdateVersion == nil)
        #expect(third.unsupportedUpdate == nil)
    }

    @Test func unreadableUnsupportedUpdateIsNil() {
        defaults.set(Data("not json".utf8), forKey: Preferences.Keys.unsupportedUpdate)
        #expect(Preferences(defaults: defaults).unsupportedUpdate == nil)
        defaults.set(Data(#"{"version": "1.2.0"}"#.utf8), forKey: Preferences.Keys.unsupportedUpdate)
        #expect(Preferences(defaults: defaults).unsupportedUpdate == nil, "no minimum system")
    }

    // MARK: Dismissed events

    @Test func dismissedEventsPersistAndNoneRemovesTheKey() {
        let dismissed = DismissedEvents().dismissing(MenuBarFixtures.workshop).dismissing(MenuBarFixtures.review)
        let first = Preferences(defaults: defaults)
        #expect(defaults.object(forKey: Preferences.Keys.dismissedEvents) == nil, "nothing is stored until something is dismissed")
        first.dismissedEvents = dismissed
        #expect(defaults.data(forKey: Preferences.Keys.dismissedEvents) != nil)

        let second = Preferences(defaults: defaults)
        #expect(second.dismissedEvents == dismissed)

        second.dismissedEvents = dismissed.restoring(MenuBarFixtures.workshop)
        #expect(Set(Preferences(defaults: defaults).dismissedEvents.occurrences.keys) == [MenuBarFixtures.review.id])
        second.dismissedEvents = DismissedEvents()
        #expect(defaults.object(forKey: Preferences.Keys.dismissedEvents) == nil)
        #expect(Preferences(defaults: defaults).dismissedEvents.isEmpty)
    }

    /// All future events of a repeating event, and an occurrence restored inside them, survive a relaunch;
    /// what 1.2.0 saved still loads.
    @Test func dismissedSeriesPersistAndSavedBy120Load() throws {
        let start = MenuBarFixtures.date(6, 9)
        let standup = Meeting(id: Meeting.occurrenceID(eventIdentifier: "standup", start: start), title: "Standup",
                              start: start, end: start.addingTimeInterval(15 * 60), seriesID: "standup")
        let tomorrow = start.addingTimeInterval(24 * 60 * 60)
        let next = Meeting(id: Meeting.occurrenceID(eventIdentifier: "standup", start: tomorrow), title: "Standup",
                           start: tomorrow, end: tomorrow.addingTimeInterval(15 * 60), seriesID: "standup")
        let dismissed = DismissedEvents().dismissing(standup, scope: .allFutureEvents).restoring(next)
        Preferences(defaults: defaults).dismissedEvents = dismissed
        let reloaded = Preferences(defaults: defaults).dismissedEvents
        #expect(reloaded == dismissed)
        #expect(reloaded.isDismissed(standup))
        #expect(!reloaded.isDismissed(next))

        let workshop = MenuBarFixtures.workshop
        defaults.set(try JSONEncoder().encode([workshop.id: workshop.end]), forKey: Preferences.Keys.dismissedEvents)
        let saved = Preferences(defaults: defaults).dismissedEvents
        #expect(saved.isDismissed(workshop))
        #expect(saved.occurrences[workshop.id]?.end == workshop.end)
    }

    @Test func unreadableDismissedEventsAreNone() {
        defaults.set(Data("not json".utf8), forKey: Preferences.Keys.dismissedEvents)
        #expect(Preferences(defaults: defaults).dismissedEvents.isEmpty)
        defaults.set(Data(#"{"val": "tonight"}"#.utf8), forKey: Preferences.Keys.dismissedEvents)
        #expect(Preferences(defaults: defaults).dismissedEvents.isEmpty)
        defaults.set("val", forKey: Preferences.Keys.dismissedEvents)
        #expect(Preferences(defaults: defaults).dismissedEvents.isEmpty, "not data at all")
    }

    /// Dismissed events aren't a setting: Restore Defaults and the other resets leave them alone.
    @Test func resetsLeaveDismissedEventsAlone() {
        let dismissed = DismissedEvents().dismissing(MenuBarFixtures.workshop)
        let preferences = Preferences(defaults: defaults)
        preferences.dismissedEvents = dismissed
        preferences.appearance = AlertAppearance(blurMode: .light, join: AlertButtonColors(fill: RGBA(rgb: 0x2563EB)))
        preferences.outOfOfficeKeywords = ["away"]

        preferences.resetAppearance()
        preferences.resetOutOfOfficeKeywords()
        preferences.applyCustomAppearance()
        #expect(preferences.dismissedEvents == dismissed)
        #expect(Preferences(defaults: defaults).dismissedEvents == dismissed)
    }

    /// The meeting store reads `dismissedEvents` in `alertableMeetings`, so a dismissal reaches the alert,
    /// the menu bar and the card through observation.
    @Test func dismissingNotifiesObservers() async {
        let preferences = Preferences(defaults: defaults)
        // Exactly one change: `confirmation` fails on none and on more than one.
        await confirmation("observers hear about the dismissal") { changed in
            withObservationTracking {
                _ = preferences.dismissedEvents
            } onChange: {
                changed()
            }
            preferences.dismissedEvents = preferences.dismissedEvents.dismissing(MenuBarFixtures.workshop)
        }
    }
}
