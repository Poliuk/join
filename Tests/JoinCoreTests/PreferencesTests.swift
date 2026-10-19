import Foundation
import Observation
import Testing
@testable import JoinCore

/// A class, not a struct, so `deinit` can remove each test's defaults: every test gets a suite of its own,
/// since Swift Testing runs them in parallel. On the main actor, like `Preferences`.
@MainActor
final class PreferencesTests {
    private typealias Keys = Preferences.Keys

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

    /// Removes the suite through a new handle, since a nonisolated `deinit` can't touch the main-actor
    /// `defaults`, then its emptied file, which would otherwise stay in the temporary folder.
    deinit {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(atPath: suiteName + ".plist")
    }

    // MARK: Defaults and persistence

    /// The defaults the user chose. A fresh start writes none of them, so a release that changes a default
    /// changes it for everyone who never picked another value.
    @Test func defaultValues() {
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.leadTime == 180)
        #expect(preferences.fullScreenAlertsEnabled)
        #expect(!preferences.notificationsEnabled, "Notify me is Never")
        #expect(preferences.notificationLeadTime == 300, "Custom… keeps 5 minutes")
        #expect(preferences.notificationPlaysSound)
        #expect(preferences.notificationScreens == .main)
        #expect(preferences.notificationAutoCloseEnabled)
        #expect(preferences.notificationAutoCloseAfter == 10 * 60)
        #expect(preferences.snoozeDurations == SnoozeDurations(first: 60, second: 300))
        #expect(preferences.alertScreens == .all)
        #expect(preferences.menuBarDisplay == .time)
        #expect(preferences.autoCloseEnabled)
        #expect(preferences.autoCloseAfter == 15 * 60)
        #expect(preferences.soundName == nil)
        #expect(!preferences.soundRepeats)
        #expect(preferences.enabledCalendarIDs == nil)
        #expect(preferences.eventsWithoutParticipants == .showAndAlert)
        #expect(preferences.appearance == .default)
        #expect(preferences.customAppearance == nil)
        #expect(preferences.outOfOfficeEvents == .listOnly)
        #expect(preferences.outOfOfficeKeywords == OutOfOfficeDetector.defaultKeywords)
        #expect(preferences.startingSoonPill == .default)
        #expect(preferences.panelListFilter == .week)
        #expect(preferences.checksForUpdates)
        #expect(preferences.lastUpdateCheck == nil)
        #expect(preferences.offeredUpdateVersion == nil)
        #expect(preferences.unsupportedUpdate == nil)
        #expect(preferences.dismissedEvents.isEmpty)
        #expect((defaults.persistentDomain(forName: suiteName) ?? [:]).isEmpty, "nothing is stored until it changes")
    }

    /// One change to each stored setting: away from its default, or, for an optional one, back to nothing.
    enum Setting: CaseIterable, Sendable {
        case leadTime
        case fullScreenAlertsEnabled
        case notificationsEnabled
        case notificationLeadTime
        case notificationPlaysSound
        case notificationScreensAll, notificationScreensSecondary, notificationScreensPointer, notificationScreensBackToMain
        case notificationAutoCloseEnabled
        case notificationAutoCloseAfter
        case snoozeDurations
        case alertScreensMain, alertScreensSecondary, alertScreensPointer, alertScreensBackToAll
        case menuBarDisplayIconOnly, menuBarDisplayTitleAndTime
        case autoCloseEnabled
        case autoCloseAfter
        case soundName, soundNameCleared
        case soundRepeats
        case enabledCalendarIDs, enabledCalendarIDsCleared
        case eventsWithoutParticipantsListOnly, eventsWithoutParticipantsExcluded
        case appearance
        case customAppearance, customAppearanceCleared
        case outOfOfficeEventsShowAndAlert, outOfOfficeEventsExcluded
        case outOfOfficeKeywords
        case startingSoonPill
        case panelListFilter
        case dismissedEvents, dismissedEventsCleared
        case checksForUpdates
        case lastUpdateCheck, lastUpdateCheckCleared
        case offeredUpdateVersion, offeredUpdateVersionCleared
        case unsupportedUpdate, unsupportedUpdateCleared
    }

    /// How a `Setting` row changes its property, through one key path for reading and writing.
    @MainActor
    struct Probe {
        let key: String
        /// Whether the change leaves a value under `key`; clearing an optional setting removes it.
        let stores: Bool
        let prepare: @MainActor (Preferences) -> Void
        let change: @MainActor (Preferences) -> Void
        let isChanged: @MainActor (Preferences) -> Bool

        init<Value: Equatable>(
            _ keyPath: ReferenceWritableKeyPath<Preferences, Value>,
            key: String,
            from start: Value? = nil,
            to value: Value,
            stores: Bool = true
        ) {
            self.key = key
            self.stores = stores
            prepare = { preferences in
                if let start { preferences[keyPath: keyPath] = start }
            }
            change = { $0[keyPath: keyPath] = value }
            isChanged = { $0[keyPath: keyPath] == value }
        }
    }

    private func makeProbe(_ setting: Setting) -> Probe {
        let look = AlertAppearance(blurMode: .light, join: AlertButtonColors(fill: RGBA(rgb: 0x2563EB)))
        let dismissed = DismissedEvents().dismissing(MenuBarFixtures.workshop).dismissing(MenuBarFixtures.review)
        let unsupported = UnsupportedUpdate(version: AppVersion(major: 1, minor: 2, patch: 0), minimumSystem: "15.0")
        let offered = AppVersion(major: 1, minor: 1, patch: 0)
        let checked = Date(timeIntervalSinceReferenceDate: 800_000_000)
        return switch setting {
        case .leadTime: Probe(\.leadTime, key: Keys.leadTime, to: 300)
        case .fullScreenAlertsEnabled: Probe(\.fullScreenAlertsEnabled, key: Keys.fullScreenAlertsEnabled, to: false)
        case .notificationsEnabled: Probe(\.notificationsEnabled, key: Keys.notificationsEnabled, to: true)
        case .notificationLeadTime: Probe(\.notificationLeadTime, key: Keys.notificationLeadTime, to: 60)
        case .notificationPlaysSound: Probe(\.notificationPlaysSound, key: Keys.notificationPlaysSound, to: false)
        case .notificationScreensAll: Probe(\.notificationScreens, key: Keys.notificationScreens, to: .all)
        case .notificationScreensSecondary: Probe(\.notificationScreens, key: Keys.notificationScreens, to: .secondary)
        case .notificationScreensPointer: Probe(\.notificationScreens, key: Keys.notificationScreens, to: .pointer)
        case .notificationScreensBackToMain: Probe(\.notificationScreens, key: Keys.notificationScreens, from: .pointer, to: .main)
        case .notificationAutoCloseEnabled: Probe(\.notificationAutoCloseEnabled, key: Keys.notificationAutoCloseEnabled, to: false)
        case .notificationAutoCloseAfter: Probe(\.notificationAutoCloseAfter, key: Keys.notificationAutoCloseAfter, to: 30 * 60)
        case .snoozeDurations: Probe(\.snoozeDurations, key: Keys.snoozeDurations, to: SnoozeDurations(first: 180, second: 600))
        case .alertScreensMain: Probe(\.alertScreens, key: Keys.alertScreens, to: .main)
        case .alertScreensSecondary: Probe(\.alertScreens, key: Keys.alertScreens, to: .secondary)
        case .alertScreensPointer: Probe(\.alertScreens, key: Keys.alertScreens, to: .pointer)
        case .alertScreensBackToAll: Probe(\.alertScreens, key: Keys.alertScreens, from: .pointer, to: .all)
        // One change, though it writes both switches.
        case .menuBarDisplayIconOnly: Probe(\.menuBarDisplay, key: Keys.menuBarShowsNextEvent, to: .iconOnly)
        case .menuBarDisplayTitleAndTime: Probe(\.menuBarDisplay, key: Keys.menuBarShowsEventTitles, to: .titleAndTime)
        case .autoCloseEnabled: Probe(\.autoCloseEnabled, key: Keys.autoCloseEnabled, to: false)
        case .autoCloseAfter: Probe(\.autoCloseAfter, key: Keys.autoCloseAfter, to: 30 * 60)
        case .soundName: Probe(\.soundName, key: Keys.soundName, to: "Glass")
        case .soundNameCleared: Probe(\.soundName, key: Keys.soundName, from: "Glass", to: nil, stores: false)
        case .soundRepeats: Probe(\.soundRepeats, key: Keys.soundRepeats, to: true)
        case .enabledCalendarIDs: Probe(\.enabledCalendarIDs, key: Keys.enabledCalendarIDs, to: ["work", "personal"])
        // Every calendar is enabled again.
        case .enabledCalendarIDsCleared: Probe(\.enabledCalendarIDs, key: Keys.enabledCalendarIDs, from: ["work"], to: nil, stores: false)
        case .eventsWithoutParticipantsListOnly: Probe(\.eventsWithoutParticipants, key: Keys.eventsWithoutParticipants, to: .listOnly)
        case .eventsWithoutParticipantsExcluded: Probe(\.eventsWithoutParticipants, key: Keys.eventsWithoutParticipants, to: .exclude)
        case .appearance: Probe(\.appearance, key: Keys.appearance, to: look)
        case .customAppearance: Probe(\.customAppearance, key: Keys.customAppearance, to: look)
        case .customAppearanceCleared: Probe(\.customAppearance, key: Keys.customAppearance, from: look, to: nil, stores: false)
        case .outOfOfficeEventsShowAndAlert: Probe(\.outOfOfficeEvents, key: Keys.outOfOfficeEvents, to: .showAndAlert)
        case .outOfOfficeEventsExcluded: Probe(\.outOfOfficeEvents, key: Keys.outOfOfficeEvents, to: .exclude)
        case .outOfOfficeKeywords: Probe(\.outOfOfficeKeywords, key: Keys.outOfOfficeKeywords, to: ["away"])
        case .startingSoonPill:
            Probe(\.startingSoonPill, key: Keys.startingSoonPill, to: StartingSoonPill(minutes: 10, fill: RGBA(rgb: 0xFFD60A), text: .black))
        case .panelListFilter: Probe(\.panelListFilter, key: Keys.panelListFilter, to: .today)
        case .dismissedEvents: Probe(\.dismissedEvents, key: Keys.dismissedEvents, to: dismissed)
        case .dismissedEventsCleared: Probe(\.dismissedEvents, key: Keys.dismissedEvents, from: dismissed, to: DismissedEvents(), stores: false)
        case .checksForUpdates: Probe(\.checksForUpdates, key: Keys.checksForUpdates, to: false)
        case .lastUpdateCheck: Probe(\.lastUpdateCheck, key: Keys.lastUpdateCheck, to: checked)
        case .lastUpdateCheckCleared: Probe(\.lastUpdateCheck, key: Keys.lastUpdateCheck, from: checked, to: nil, stores: false)
        case .offeredUpdateVersion: Probe(\.offeredUpdateVersion, key: Keys.offeredUpdateVersion, to: offered)
        case .offeredUpdateVersionCleared: Probe(\.offeredUpdateVersion, key: Keys.offeredUpdateVersion, from: offered, to: nil, stores: false)
        case .unsupportedUpdate: Probe(\.unsupportedUpdate, key: Keys.unsupportedUpdate, to: unsupported)
        case .unsupportedUpdateCleared: Probe(\.unsupportedUpdate, key: Keys.unsupportedUpdate, from: unsupported, to: nil, stores: false)
        }
    }

    /// Every setting is stored as it changes, reads back after a relaunch, and tells its observers. Each is wired
    /// by hand (`access` and `withMutation` with its own key path), and SwiftUI and the meeting store see a
    /// change only through observation: the store reads `dismissedEvents`, so a dismissal reaches the alert,
    /// the menu bar and the card.
    @Test(arguments: Setting.allCases)
    func everySettingPersistsAndNotifiesObservers(_ setting: Setting) async {
        let probe = makeProbe(setting)
        let preferences = Preferences(defaults: defaults)
        probe.prepare(preferences)
        #expect(!probe.isChanged(preferences), "the row changes something")

        // Exactly one change: `confirmation` fails on none and on more than one.
        await confirmation("observers hear about the change") { changed in
            withObservationTracking {
                _ = probe.isChanged(preferences)
            } onChange: {
                changed()
            }
            probe.change(preferences)
        }
        #expect(probe.isChanged(preferences))
        #expect((defaults.object(forKey: probe.key) != nil) == probe.stores)
        #expect(probe.isChanged(Preferences(defaults: defaults)), "after a relaunch")
    }

    /// Something stored that can't be read, from a damaged file or another build, loads as the default.
    struct Unreadable: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let key: String
        let stored: any Sendable
        let fellBack: @MainActor @Sendable (Preferences) -> Bool
    }

    nonisolated static let unreadable: [Unreadable] = [
        Unreadable(testDescription: "look", key: Keys.appearance, stored: Data("not json".utf8)) {
            $0.appearance == .default && $0.customAppearance == nil
        },
        Unreadable(testDescription: "menu bar pill", key: Keys.startingSoonPill, stored: Data("not json".utf8)) {
            $0.startingSoonPill == .default
        },
        Unreadable(testDescription: "snooze buttons without two durations", key: Keys.snoozeDurations, stored: [120.0]) {
            $0.snoozeDurations == Preferences.defaultSnoozeDurations
        },
        Unreadable(testDescription: "the notification's Show on", key: Keys.notificationScreens, stored: "everywhere") {
            $0.notificationScreens == .main
        },
        Unreadable(testDescription: "panel list filter", key: Keys.panelListFilter, stored: "everything") {
            $0.panelListFilter == .week
        },
        Unreadable(testDescription: "dismissed events", key: Keys.dismissedEvents, stored: Data("not json".utf8)) {
            $0.dismissedEvents.isEmpty
        },
        Unreadable(testDescription: "unsupported update", key: Keys.unsupportedUpdate, stored: Data("not json".utf8)) {
            $0.unsupportedUpdate == nil
        },
        Unreadable(
            testDescription: "unsupported update with a version that can't be read", key: Keys.unsupportedUpdate,
            stored: Data(#"{"version":"1.2","minimumSystem":"15.0"}"#.utf8)
        ) {
            $0.unsupportedUpdate == nil
        },
        Unreadable(testDescription: "offered update version", key: Keys.offeredUpdateVersion, stored: "1.1") {
            $0.offeredUpdateVersion == nil
        },
    ]

    @Test(arguments: unreadable)
    func anUnreadableStoredValueFallsBackToTheDefault(_ value: Unreadable) {
        defaults.set(value.stored, forKey: value.key)
        #expect(value.fellBack(Preferences(defaults: defaults)))
    }

    /// A value that can't be stored as JSON (here a color with a NaN component, which JSON can't hold) leaves
    /// what was stored, so a relaunch still has the last value that could be saved.
    @Test func aValueThatCantBeStoredKeepsWhatWasStored() {
        let preferences = Preferences(defaults: defaults)
        let pill = StartingSoonPill(minutes: 10, fill: RGBA(rgb: 0xFFD60A))
        preferences.startingSoonPill = pill
        let stored = defaults.data(forKey: Keys.startingSoonPill)
        #expect(stored != nil)

        preferences.startingSoonPill = StartingSoonPill(minutes: 10, fill: RGBA(red: .nan, green: 0, blue: 0))
        #expect(defaults.data(forKey: Keys.startingSoonPill) == stored)
        #expect(Preferences(defaults: defaults).startingSoonPill == pill)
    }

    /// Alert me is in whole minutes, never below 0: set or loaded, a lead time rounds to the nearest minute.
    @Test(arguments: [(150.0, 180.0), (89, 60), (-60, 0), (210, 240)])
    func leadTimeIsWholeMinutes(seconds: TimeInterval, expected: TimeInterval) {
        defaults.set(seconds, forKey: Keys.leadTime)
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.leadTime == expected, "loaded")
        preferences.leadTime = seconds
        #expect(preferences.leadTime == expected, "set")
    }

    /// Notify me is in whole minutes too, never below 0, set or loaded, like Alert me.
    @Test(arguments: [(150.0, 180.0), (89, 60), (-60, 0), (0, 0), (7260, 7260)])
    func notificationLeadTimeIsWholeMinutes(seconds: TimeInterval, expected: TimeInterval) {
        defaults.set(seconds, forKey: Keys.notificationLeadTime)
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.notificationLeadTime == expected, "loaded")
        preferences.notificationLeadTime = seconds
        #expect(preferences.notificationLeadTime == expected, "set")
    }

    /// The alert's auto-close timer gets this value, so it's never under a minute, set or loaded: a 0 would close
    /// every full-screen alert as it appears.
    @Test(arguments: [(0.0, 60.0), (30, 60), (-300, 60), (60, 60), (90, 90)])
    func autoCloseIsAtLeastAMinute(seconds: TimeInterval, expected: TimeInterval) {
        defaults.set(seconds, forKey: Keys.autoCloseAfter)
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.autoCloseAfter == expected, "loaded")
        preferences.autoCloseAfter = seconds
        #expect(preferences.autoCloseAfter == expected, "set")
    }

    /// The card's auto-close timer gets this value, so it's whole minutes, as its pop-up shows it, and never
    /// under a minute, set or loaded.
    @Test(arguments: [(0.0, 60.0), (30, 60), (-300, 60), (60, 60), (89, 60), (90, 120), (150, 180), (600, 600)])
    func notificationAutoCloseIsWholeMinutesOfAtLeastOne(seconds: TimeInterval, expected: TimeInterval) {
        defaults.set(seconds, forKey: Keys.notificationAutoCloseAfter)
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.notificationAutoCloseAfter == expected, "loaded")
        preferences.notificationAutoCloseAfter = seconds
        #expect(preferences.notificationAutoCloseAfter == expected, "set")
    }

    /// The card's Show on and Close automatically are its own: changing them leaves the full-screen alert's as
    /// they were, and the other way round.
    @Test func eachKindKeepsItsOwnScreensAndAutoClose() {
        let preferences = Preferences(defaults: defaults)
        preferences.notificationScreens = .pointer
        preferences.notificationAutoCloseEnabled = false
        preferences.notificationAutoCloseAfter = 5 * 60
        preferences.alertScreens = .secondary
        preferences.autoCloseAfter = 30 * 60

        let reopened = Preferences(defaults: defaults)
        #expect(reopened.notificationScreens == .pointer)
        #expect(!reopened.notificationAutoCloseEnabled)
        #expect(reopened.notificationAutoCloseAfter == 5 * 60)
        #expect(reopened.alertScreens == .secondary)
        #expect(reopened.autoCloseEnabled)
        #expect(reopened.autoCloseAfter == 30 * 60)
    }

    /// Stored as earlier builds stored them, so their settings still read: the snooze buttons as two
    /// seconds, the menu bar's choice as two switches, an offered version as its "1.1.0" string.
    @Test func settingsKeepTheShapesEarlierBuildsStored() {
        defaults.set([120.0, 600.0], forKey: Keys.snoozeDurations)
        defaults.set(true, forKey: Keys.menuBarShowsNextEvent)
        defaults.set(true, forKey: Keys.menuBarShowsEventTitles)
        defaults.set("1.1.0", forKey: Keys.offeredUpdateVersion)
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.snoozeDurations == SnoozeDurations(first: 120, second: 600))
        #expect(preferences.menuBarDisplay == .titleAndTime)
        #expect(preferences.offeredUpdateVersion == AppVersion(major: 1, minor: 1, patch: 0))

        preferences.snoozeDurations.second = 300
        preferences.menuBarDisplay = .iconOnly
        preferences.offeredUpdateVersion = AppVersion(major: 1, minor: 2, patch: 0)
        #expect(defaults.array(forKey: Keys.snoozeDurations) as? [TimeInterval] == [120, 300])
        #expect(defaults.object(forKey: Keys.menuBarShowsNextEvent) as? Bool == false)
        #expect(defaults.object(forKey: Keys.menuBarShowsEventTitles) as? Bool == false)
        #expect(defaults.string(forKey: Keys.offeredUpdateVersion) == "1.2.0")
    }

    /// One choice in Settings, stored as the two switches, and read back after a relaunch.
    @Test(arguments: MenuBarDisplay.allCases)
    func menuBarDisplayIsStoredAsTwoSwitches(_ display: MenuBarDisplay) {
        let preferences = Preferences(defaults: defaults)
        preferences.menuBarDisplay = display
        #expect(defaults.object(forKey: Keys.menuBarShowsNextEvent) as? Bool == display.showsNextEvent)
        #expect(defaults.object(forKey: Keys.menuBarShowsEventTitles) as? Bool == display.showsTitles)
        #expect(Preferences(defaults: defaults).menuBarDisplay == display)
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

    @Test func neverKeepsTheLeadTimeForWhenAlertsComeBack() {
        let preferences = Preferences(defaults: defaults)
        preferences.leadTime = 300
        preferences.fullScreenAlertsEnabled = false

        let reopened = Preferences(defaults: defaults)
        #expect(!reopened.fullScreenAlertsEnabled)
        #expect(reopened.leadTime == 300)
    }

    /// Each kind has its own time and Never: Notify me's Never keeps its time, and neither kind's time or
    /// Never touches the other's.
    @Test func eachKindKeepsItsOwnTimeAndNever() {
        let preferences = Preferences(defaults: defaults)
        preferences.notificationLeadTime = 60
        preferences.notificationsEnabled = true
        preferences.leadTime = 0
        preferences.fullScreenAlertsEnabled = false
        preferences.notificationsEnabled = false

        let reopened = Preferences(defaults: defaults)
        #expect(!reopened.notificationsEnabled)
        #expect(reopened.notificationLeadTime == 60)
        #expect(!reopened.fullScreenAlertsEnabled)
        #expect(reopened.leadTime == 0)
    }

    // MARK: Settings from earlier builds

    /// An upgrade from 1.2.x, whose settings have no notification keys, keeps exactly its behaviour: every
    /// stored value carries over, Notify me reads Never, so no card shows, the card's own settings read their
    /// defaults whatever the full-screen alert's say, and reading writes nothing new.
    @Test func anUpgradeFrom12KeepsNotificationsOff() {
        let stored: [String: any Sendable] = [
            Keys.leadTime: 60.0,
            Keys.fullScreenAlertsEnabled: true,
            Keys.snoozeDurations: [120.0, 600.0],
            Keys.soundName: "Glass",
            Keys.autoCloseEnabled: false,
            Keys.alertScreens: "pointer",
        ]
        for (key, value) in stored { defaults.set(value, forKey: key) }
        let before = Set((defaults.persistentDomain(forName: suiteName) ?? [:]).keys)

        let preferences = Preferences(defaults: defaults)
        #expect(!preferences.notificationsEnabled)
        #expect(preferences.notificationLeadTime == Preferences.defaultNotificationLeadTime)
        #expect(preferences.notificationPlaysSound)
        #expect(preferences.notificationScreens == .main)
        #expect(preferences.notificationAutoCloseEnabled)
        #expect(preferences.notificationAutoCloseAfter == Preferences.defaultNotificationAutoCloseAfter)
        #expect(preferences.leadTime == 60)
        #expect(preferences.fullScreenAlertsEnabled)
        #expect(preferences.snoozeDurations == SnoozeDurations(first: 120, second: 600))
        #expect(preferences.soundName == "Glass")
        #expect(!preferences.autoCloseEnabled)
        #expect(Set((defaults.persistentDomain(forName: suiteName) ?? [:]).keys) == before, "nothing is written")
    }

    /// Switches stored by earlier builds, read until a choice is stored.
    struct LegacyKeys: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let stored: [String: any Sendable]
        let eventsWithoutParticipants: EventVisibility
        let outOfOfficeEvents: EventVisibility
    }

    /// 1.1's switch for events with no participants, on by default, and the out-of-office switches of 1.0 and
    /// 1.1, alert off and list on by default: alerting wins, so an upgrade keeps every alert the user had.
    nonisolated static let legacyKeys: [LegacyKeys] = [
        LegacyKeys(testDescription: "1.1's no-participants switch on", stored: [Keys.legacyShowsEventsWithoutParticipants: true],
                   eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .listOnly),
        LegacyKeys(testDescription: "1.1's no-participants switch off", stored: [Keys.legacyShowsEventsWithoutParticipants: false],
                   eventsWithoutParticipants: .exclude, outOfOfficeEvents: .listOnly),
        LegacyKeys(testDescription: "out-of-office alert on, list on",
                   stored: [Keys.legacyAlertForOutOfOffice: true, Keys.legacyShowOutOfOfficeInList: true],
                   eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert),
        LegacyKeys(testDescription: "out-of-office alert off, list on",
                   stored: [Keys.legacyAlertForOutOfOffice: false, Keys.legacyShowOutOfOfficeInList: true],
                   eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .listOnly),
        LegacyKeys(testDescription: "out-of-office alert off, list off",
                   stored: [Keys.legacyAlertForOutOfOffice: false, Keys.legacyShowOutOfOfficeInList: false],
                   eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .exclude),
        LegacyKeys(testDescription: "out-of-office alert on, list off",
                   stored: [Keys.legacyAlertForOutOfOffice: true, Keys.legacyShowOutOfOfficeInList: false],
                   eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert),
        LegacyKeys(testDescription: "only out-of-office alert on", stored: [Keys.legacyAlertForOutOfOffice: true],
                   eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert),
        LegacyKeys(testDescription: "only out-of-office list off", stored: [Keys.legacyShowOutOfOfficeInList: false],
                   eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .exclude),
        LegacyKeys(testDescription: "before 1.0, skip off", stored: [Keys.legacySkipOutOfOffice: false],
                   eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert),
        LegacyKeys(testDescription: "before 1.0, skip on", stored: [Keys.legacySkipOutOfOffice: true],
                   eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .listOnly),
        LegacyKeys(testDescription: "skip on, list off",
                   stored: [Keys.legacySkipOutOfOffice: true, Keys.legacyShowOutOfOfficeInList: false],
                   eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .exclude),
        LegacyKeys(testDescription: "skip on, list off, and 1.1's alert on, which wins over the older key",
                   stored: [Keys.legacySkipOutOfOffice: true, Keys.legacyShowOutOfOfficeInList: false, Keys.legacyAlertForOutOfOffice: true],
                   eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .showAndAlert),
        LegacyKeys(testDescription: "an unknown stored choice",
                   stored: [Keys.eventsWithoutParticipants: "hide", Keys.outOfOfficeEvents: "hide"],
                   eventsWithoutParticipants: .showAndAlert, outOfOfficeEvents: .listOnly),
        LegacyKeys(testDescription: "an unknown stored choice over the switches",
                   stored: [Keys.eventsWithoutParticipants: "hide", Keys.outOfOfficeEvents: "hide",
                            Keys.legacyShowsEventsWithoutParticipants: false, Keys.legacyAlertForOutOfOffice: true],
                   eventsWithoutParticipants: .exclude, outOfOfficeEvents: .showAndAlert),
    ]

    @Test(arguments: legacyKeys)
    func legacySwitchesAreMigrated(_ legacy: LegacyKeys) {
        for (key, value) in legacy.stored { defaults.set(value, forKey: key) }
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.eventsWithoutParticipants == legacy.eventsWithoutParticipants)
        #expect(preferences.outOfOfficeEvents == legacy.outOfOfficeEvents)
        #expect(legacy.stored.keys.allSatisfy { defaults.object(forKey: $0) != nil }, "reading removes nothing")
    }

    @Test func aStoredChoiceWinsOverTheLegacySwitchesAndRemovesThem() {
        defaults.set(false, forKey: Keys.legacyShowsEventsWithoutParticipants)
        defaults.set(true, forKey: Keys.legacyAlertForOutOfOffice)
        defaults.set(true, forKey: Keys.legacySkipOutOfOffice)
        defaults.set(false, forKey: Keys.legacyShowOutOfOfficeInList)
        defaults.set("listOnly", forKey: Keys.eventsWithoutParticipants)
        defaults.set("listOnly", forKey: Keys.outOfOfficeEvents)
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.eventsWithoutParticipants == .listOnly)
        #expect(preferences.outOfOfficeEvents == .listOnly)

        preferences.outOfOfficeEvents = .exclude
        #expect(defaults.object(forKey: Keys.legacyAlertForOutOfOffice) == nil)
        #expect(defaults.object(forKey: Keys.legacyShowOutOfOfficeInList) == nil)
        #expect(defaults.object(forKey: Keys.legacySkipOutOfOffice) == nil)
        #expect(defaults.object(forKey: Keys.legacyShowsEventsWithoutParticipants) != nil, "each choice clears only its own")

        preferences.eventsWithoutParticipants = .exclude
        #expect(defaults.object(forKey: Keys.legacyShowsEventsWithoutParticipants) == nil)
    }

    @Test func legacyShowOnAllScreensIsMigrated() {
        defaults.set(false, forKey: Keys.legacyShowOnAllScreens)
        #expect(Preferences(defaults: defaults).alertScreens == .main)

        let preferences = Preferences(defaults: defaults)
        preferences.alertScreens = .pointer
        #expect(Preferences(defaults: defaults).alertScreens == .pointer)
        #expect(defaults.object(forKey: Keys.legacyShowOnAllScreens) == nil)
    }

    /// The legacy switch was the full-screen alert's only: the card's Show on keeps its own default.
    @Test func legacyShowOnAllScreensLeavesTheNotificationAlone() {
        defaults.set(true, forKey: Keys.legacyShowOnAllScreens)
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.alertScreens == .all)
        #expect(preferences.notificationScreens == .main)
    }

    // MARK: Appearance and the Custom card

    /// Appearance's Restore Defaults puts back the look only: since 1.2.0 snooze, auto-close and the pill
    /// live on other panes, and the Custom card keeps the user's look.
    @Test func restoreDefaultsRestoresTheLookOnly() {
        let preferences = Preferences(defaults: defaults)
        let custom = AlertAppearance(blurMode: .light, join: AlertButtonColors(fill: RGBA(rgb: 0x2563EB)))
        let pill = StartingSoonPill(minutes: 10, fill: RGBA(rgb: 0xFFD60A), text: .black)
        preferences.appearance = custom
        preferences.snoozeDurations = SnoozeDurations(first: 180, second: 600)
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
        #expect(reopened.customAppearance == custom, "the Custom card keeps the look")
        #expect(reopened.snoozeDurations == SnoozeDurations(first: 180, second: 600))
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

    /// What an earlier build stored: the look as JSON, and the Custom card's look.
    struct StoredLook: Sendable, CustomTestStringConvertible {
        let testDescription: String
        var appearance: String?
        var customAppearance: String?
        /// The preset the look loads as; nil for a look of the user's own, which the Custom card gets.
        let loadsAs: AlertAppearancePreset?
    }

    nonisolated static let storedLooks: [StoredLook] = [
        StoredLook(
            testDescription: "1.1's blue Join on Light blur",
            appearance: #"{"version":2,"blurMode":"light","tintStrength":0.35,"join":{"fill":{"red":0.1450980392156863,"green":0.38823529411764707,"blue":0.9215686274509803,"alpha":1},"fillOpacity":1},"dismissAndSnooze":{"fillOpacity":1}}"#,
            loadsAs: nil
        ),
        // One 8-bit step from Dark's buttons: #FFFFFF28, not #FFFFFF29.
        StoredLook(
            testDescription: "1.1's Fill opacity at 97 % on Dark",
            appearance: #"{"version":2,"blurMode":"dark","tintStrength":0.35,"join":{"fillOpacity":1},"dismissAndSnooze":{"fillOpacity":0.97}}"#,
            loadsAs: nil
        ),
        StoredLook(
            testDescription: "1.1's High contrast, with a pure black Join label",
            appearance: #"{"version":2,"blurMode":"dark","tint":{"red":0,"green":0,"blue":0,"alpha":1},"tintStrength":0.7,"join":{"text":{"red":0,"green":0,"blue":0,"alpha":1},"fill":{"red":1,"green":0.8392156862745098,"blue":0.0392156862745098,"alpha":1},"fillOpacity":1},"dismissAndSnooze":{"fill":{"red":1,"green":1,"blue":1,"alpha":1},"fillOpacity":0.22}}"#,
            loadsAs: .highContrast
        ),
        StoredLook(
            testDescription: "a card look that matches a preset",
            customAppearance: #"{"version":3,"blurMode":"light","tintStrength":0.35,"join":{"fillOpacity":1},"dismissAndSnooze":{"fillOpacity":1}}"#,
            loadsAs: .dark
        ),
        StoredLook(testDescription: "an unreadable look", appearance: "not json", loadsAs: .dark),
    ]

    /// A look of the user's own saved before the Custom card existed opens on the card, saved at once so a preset
    /// click can't lose it. A look that matches a preset, or can't be read, seeds nothing, and a stored card
    /// look that matches a preset is ignored.
    @Test(arguments: storedLooks)
    func theCustomCardIsSeededFromAStoredLookOfTheUsersOwn(_ stored: StoredLook) {
        if let json = stored.appearance { defaults.set(Data(json.utf8), forKey: Keys.appearance) }
        if let json = stored.customAppearance { defaults.set(Data(json.utf8), forKey: Keys.customAppearance) }
        let preferences = Preferences(defaults: defaults)

        if let preset = stored.loadsAs {
            #expect(preferences.appearance == preset.appearance)
            #expect(preferences.customAppearance == nil)
            if stored.customAppearance == nil {
                #expect(defaults.object(forKey: Keys.customAppearance) == nil, "nothing written")
            }
        } else {
            let seeded = preferences.appearance
            #expect(seeded.style == .custom)
            #expect(preferences.customAppearance == seeded)
            preferences.appearance = AlertAppearancePreset.dark.appearance
            #expect(Preferences(defaults: defaults).customAppearance == seeded)
        }
    }

    // MARK: Dismissed events

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
        #expect(preferences.outOfOfficeKeywords == OutOfOfficeDetector.defaultKeywords, "the keywords' reset works")
        #expect(preferences.dismissedEvents == dismissed)
        #expect(Preferences(defaults: defaults).dismissedEvents == dismissed)
    }
}
