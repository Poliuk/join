import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.poliuk.join", category: "preferences")

/// All user-configurable settings. One owner, persisted to UserDefaults on every change,
/// observable by SwiftUI through the Observation framework. On the main actor, where the views that observe
/// it and the app that changes it run: the one isolated type in JoinCore.
@MainActor
@Observable
public final class Preferences {
    /// Internal: writing these keys directly would bypass the observation, the clamping and the checks that
    /// each setter applies.
    enum Keys {
        static let leadTime = "leadTime"
        static let fullScreenAlertsEnabled = "fullScreenAlertsEnabled"
        /// Notify me, new in 1.3.0: absent before, so every earlier install reads the defaults (Never, 5 minutes
        /// kept, sound on) and nothing is sent until the user picks a time.
        static let notificationsEnabled = "notificationsEnabled"
        static let notificationLeadTime = "notificationLeadTime"
        static let notificationPlaysSound = "notificationPlaysSound"
        static let snoozeDurations = "snoozeDurations"
        static let alertScreens = "alertScreens"
        /// Earlier builds stored a Bool here; true maps to `.all`, false to `.main`.
        static let legacyShowOnAllScreens = "showOnAllScreens"
        static let menuBarShowsEventTitles = "menuBarShowsEventTitles"
        static let autoCloseEnabled = "autoCloseEnabled"
        static let autoCloseAfter = "autoCloseAfter"
        static let soundName = "soundName"
        static let soundRepeats = "soundRepeats"
        static let enabledCalendarIDs = "enabledCalendarIDs"
        static let eventsWithoutParticipants = "eventsWithoutParticipants"
        /// 1.1 stored a switch here; true maps to `.showAndAlert`, false to `.exclude`.
        static let legacyShowsEventsWithoutParticipants = "showsEventsWithoutParticipants"
        static let menuBarShowsNextEvent = "menuBarShowsNextEvent"
        static let appearance = "appearance"
        /// The look on Appearance's Custom card, absent until there's one.
        static let customAppearance = "customAppearance"
        static let outOfOfficeEvents = "outOfOfficeEvents"
        /// 1.0 and 1.1 stored two switches for out-of-office events, read into `outOfOfficeEvents` until it
        /// is set: whether they alert, and whether the panel lists them.
        static let legacyAlertForOutOfOffice = "alertForOutOfOffice"
        static let legacyShowOutOfOfficeInList = "showOutOfOfficeInList"
        /// Builds before 1.0 stored the inverse of `legacyAlertForOutOfOffice` under this key.
        static let legacySkipOutOfOffice = "skipOutOfOffice"
        static let outOfOfficeKeywords = "outOfOfficeKeywords"
        static let startingSoonPill = "startingSoonPill"
        static let panelListFilter = "panelListFilter"
        /// The occurrences and series dismissed from the menu bar panel, as JSON (1.2.0's plain object of
        /// occurrence id → end still reads); absent while there are none.
        static let dismissedEvents = "dismissedEvents"
        static let checksForUpdates = "checksForUpdates"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let offeredUpdateVersion = "offeredUpdateVersion"
        static let unsupportedUpdate = "unsupportedUpdate"
    }

    // Constants, so they're nonisolated: any caller reads them without the main actor, like `Keys` (a nested
    // type, which the class's isolation doesn't reach). Isolated, another module could only read them on the
    // main actor or with `await`.
    nonisolated public static let defaultLeadTime: TimeInterval = 3 * 60
    /// The time Notify me keeps while it is Never, which Custom… shows: 5 minutes.
    nonisolated public static let defaultNotificationLeadTime: TimeInterval = 5 * 60
    nonisolated public static let defaultSnoozeDurations = SnoozeDurations(first: 60, second: 5 * 60)
    nonisolated public static let defaultAutoCloseAfter: TimeInterval = 15 * 60

    private let defaults: UserDefaults

    @ObservationIgnored private var _leadTime: TimeInterval
    @ObservationIgnored private var _fullScreenAlertsEnabled: Bool
    @ObservationIgnored private var _notificationsEnabled: Bool
    @ObservationIgnored private var _notificationLeadTime: TimeInterval
    @ObservationIgnored private var _notificationPlaysSound: Bool
    @ObservationIgnored private var _snoozeDurations: SnoozeDurations
    @ObservationIgnored private var _alertScreens: AlertScreens
    @ObservationIgnored private var _menuBarDisplay: MenuBarDisplay
    @ObservationIgnored private var _autoCloseEnabled: Bool
    @ObservationIgnored private var _autoCloseAfter: TimeInterval
    @ObservationIgnored private var _soundName: String?
    @ObservationIgnored private var _soundRepeats: Bool
    @ObservationIgnored private var _enabledCalendarIDs: Set<String>?
    @ObservationIgnored private var _eventsWithoutParticipants: EventVisibility
    @ObservationIgnored private var _appearance: AlertAppearance
    @ObservationIgnored private var _customAppearance: AlertAppearance?
    @ObservationIgnored private var _outOfOfficeEvents: EventVisibility
    @ObservationIgnored private var _outOfOfficeKeywords: [String]
    @ObservationIgnored private var _startingSoonPill: StartingSoonPill
    @ObservationIgnored private var _panelListFilter: PanelListFilter
    @ObservationIgnored private var _dismissedEvents: DismissedEvents
    @ObservationIgnored private var _checksForUpdates: Bool
    @ObservationIgnored private var _lastUpdateCheck: Date?
    @ObservationIgnored private var _offeredUpdateVersion: AppVersion?
    @ObservationIgnored private var _unsupportedUpdate: UnsupportedUpdate?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        _leadTime = Self.wholeMinutes(defaults.object(forKey: Keys.leadTime) as? TimeInterval ?? Self.defaultLeadTime)
        _fullScreenAlertsEnabled = defaults.object(forKey: Keys.fullScreenAlertsEnabled) as? Bool ?? true
        _notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? false
        _notificationLeadTime = Self.wholeMinutes(
            defaults.object(forKey: Keys.notificationLeadTime) as? TimeInterval ?? Self.defaultNotificationLeadTime
        )
        _notificationPlaysSound = defaults.object(forKey: Keys.notificationPlaysSound) as? Bool ?? true
        _snoozeDurations = (defaults.array(forKey: Keys.snoozeDurations) as? [TimeInterval]).flatMap(SnoozeDurations.init)
            ?? Self.defaultSnoozeDurations
        if let raw = defaults.string(forKey: Keys.alertScreens), let stored = AlertScreens(rawValue: raw) {
            _alertScreens = stored
        } else if let legacy = defaults.object(forKey: Keys.legacyShowOnAllScreens) as? Bool {
            _alertScreens = legacy ? .all : .main
        } else {
            _alertScreens = .all
        }
        _menuBarDisplay = MenuBarDisplay(
            showsNextEvent: defaults.object(forKey: Keys.menuBarShowsNextEvent) as? Bool ?? true,
            showsTitles: defaults.object(forKey: Keys.menuBarShowsEventTitles) as? Bool ?? false
        )
        _autoCloseEnabled = defaults.object(forKey: Keys.autoCloseEnabled) as? Bool ?? true
        _autoCloseAfter = Self.atLeastAMinute(defaults.object(forKey: Keys.autoCloseAfter) as? TimeInterval ?? Self.defaultAutoCloseAfter)
        _soundName = defaults.string(forKey: Keys.soundName)
        _soundRepeats = defaults.object(forKey: Keys.soundRepeats) as? Bool ?? false
        _enabledCalendarIDs = (defaults.array(forKey: Keys.enabledCalendarIDs) as? [String]).map(Set.init)
        _eventsWithoutParticipants = defaults.string(forKey: Keys.eventsWithoutParticipants).flatMap(EventVisibility.init(rawValue:))
            ?? Self.legacyEventsWithoutParticipants(in: defaults)
        _appearance = defaults.decodedJSON(AlertAppearance.self, forKey: Keys.appearance) ?? .default
        if let stored = defaults.decodedJSON(AlertAppearance.self, forKey: Keys.customAppearance) {
            _customAppearance = stored.matchingPreset == nil ? stored : nil
        } else if _appearance.matchingPreset == nil {
            // A look of the user's own, saved before the Custom card existed, becomes the card's.
            _customAppearance = _appearance
            defaults.setJSON(_appearance, forKey: Keys.customAppearance)
        } else {
            _customAppearance = nil
        }
        _outOfOfficeEvents = defaults.string(forKey: Keys.outOfOfficeEvents).flatMap(EventVisibility.init(rawValue:))
            ?? Self.legacyOutOfOfficeEvents(in: defaults)
        _outOfOfficeKeywords = defaults.array(forKey: Keys.outOfOfficeKeywords) as? [String] ?? OutOfOfficeDetector.defaultKeywords
        _startingSoonPill = defaults.decodedJSON(StartingSoonPill.self, forKey: Keys.startingSoonPill) ?? .default
        _panelListFilter = defaults.string(forKey: Keys.panelListFilter).flatMap(PanelListFilter.init(rawValue:)) ?? .week
        _dismissedEvents = defaults.decodedJSON(DismissedEvents.self, forKey: Keys.dismissedEvents) ?? DismissedEvents()
        _checksForUpdates = defaults.object(forKey: Keys.checksForUpdates) as? Bool ?? true
        _lastUpdateCheck = defaults.object(forKey: Keys.lastUpdateCheck) as? Date
        _offeredUpdateVersion = defaults.string(forKey: Keys.offeredUpdateVersion).flatMap(AppVersion.init)
        _unsupportedUpdate = defaults.decodedJSON(UnsupportedUpdate.self, forKey: Keys.unsupportedUpdate)
    }

    /// 1.1's switch, on by default: on showed these events like any other, off left them out.
    private static func legacyEventsWithoutParticipants(in defaults: UserDefaults) -> EventVisibility {
        let shown = defaults.object(forKey: Keys.legacyShowsEventsWithoutParticipants) as? Bool ?? true
        return shown ? .showAndAlert : .exclude
    }

    /// The two switches of 1.0 and 1.1, alert off and list on by default. Alert on keeps the events alerting
    /// whatever the list switch said; with both off they were out of sight, so they're excluded.
    private static func legacyOutOfOfficeEvents(in defaults: UserDefaults) -> EventVisibility {
        let alerts: Bool
        if let stored = defaults.object(forKey: Keys.legacyAlertForOutOfOffice) as? Bool {
            alerts = stored
        } else if let skip = defaults.object(forKey: Keys.legacySkipOutOfOffice) as? Bool {
            alerts = !skip
        } else {
            alerts = false
        }
        if alerts { return .showAndAlert }
        let listed = defaults.object(forKey: Keys.legacyShowOutOfOfficeInList) as? Bool ?? true
        return listed ? .listOnly : .exclude
    }

    /// Seconds before the meeting start at which the full-screen alert fires, always a whole number of minutes.
    public var leadTime: TimeInterval {
        get { access(keyPath: \.leadTime); return _leadTime }
        set {
            withMutation(keyPath: \.leadTime) {
                _leadTime = Self.wholeMinutes(newValue)
                defaults.set(_leadTime, forKey: Keys.leadTime)
            }
        }
    }

    private static func wholeMinutes(_ seconds: TimeInterval) -> TimeInterval {
        max(0, (seconds / 60).rounded()) * 60
    }

    /// False when Alert me is set to Never: no full-screen alert is scheduled or shown, while the menu bar
    /// item, its pill, the panel and notifications carry on. `leadTime` keeps the last time chosen. On by default.
    public var fullScreenAlertsEnabled: Bool {
        get { access(keyPath: \.fullScreenAlertsEnabled); return _fullScreenAlertsEnabled }
        set {
            withMutation(keyPath: \.fullScreenAlertsEnabled) {
                _fullScreenAlertsEnabled = newValue
                defaults.set(newValue, forKey: Keys.fullScreenAlertsEnabled)
            }
        }
    }

    /// False while Notify me is set to Never, the default for everyone, new installs and upgrades alike: no
    /// notification is planned or sent, and macOS isn't asked for permission. `notificationLeadTime` keeps the
    /// last time chosen. Independent of `fullScreenAlertsEnabled`: each kind has its own time or Never.
    public var notificationsEnabled: Bool {
        get { access(keyPath: \.notificationsEnabled); return _notificationsEnabled }
        set {
            withMutation(keyPath: \.notificationsEnabled) {
                _notificationsEnabled = newValue
                defaults.set(newValue, forKey: Keys.notificationsEnabled)
            }
        }
    }

    /// Seconds before the meeting start at which the notification is sent, always a whole number of minutes,
    /// like `leadTime`, and set independently of it. 5 minutes by default, kept while Notify me is Never.
    public var notificationLeadTime: TimeInterval {
        get { access(keyPath: \.notificationLeadTime); return _notificationLeadTime }
        set {
            withMutation(keyPath: \.notificationLeadTime) {
                _notificationLeadTime = Self.wholeMinutes(newValue)
                defaults.set(_notificationLeadTime, forKey: Keys.notificationLeadTime)
            }
        }
    }

    /// Play sound: on, a notification plays macOS's notification sound; off, it's silent. On by default.
    /// macOS's own sound setting for Join! can still silence it (`NotificationStatus.soundOff`).
    public var notificationPlaysSound: Bool {
        get { access(keyPath: \.notificationPlaysSound); return _notificationPlaysSound }
        set {
            withMutation(keyPath: \.notificationPlaysSound) {
                _notificationPlaysSound = newValue
                defaults.set(newValue, forKey: Keys.notificationPlaysSound)
            }
        }
    }

    /// The two snooze durations, stored as a two-element array of seconds: the full-screen alert's two snooze
    /// buttons and the notification's two Snooze actions, shared by both kinds. One minute and 5 minutes by
    /// default, and when what's stored doesn't have two entries.
    public var snoozeDurations: SnoozeDurations {
        get { access(keyPath: \.snoozeDurations); return _snoozeDurations }
        set {
            withMutation(keyPath: \.snoozeDurations) {
                _snoozeDurations = newValue
                defaults.set(newValue.all, forKey: Keys.snoozeDurations)
            }
        }
    }

    public var alertScreens: AlertScreens {
        get { access(keyPath: \.alertScreens); return _alertScreens }
        set {
            withMutation(keyPath: \.alertScreens) {
                _alertScreens = newValue
                defaults.set(newValue.rawValue, forKey: Keys.alertScreens)
                defaults.removeObject(forKey: Keys.legacyShowOnAllScreens)
            }
        }
    }

    /// What the menu bar item shows next to its icon: Time until next event by default. Stored as the two
    /// switches earlier builds kept, whether it shows the next event and whether the event's title takes the
    /// place of "Next", both written in one change.
    public var menuBarDisplay: MenuBarDisplay {
        get { access(keyPath: \.menuBarDisplay); return _menuBarDisplay }
        set {
            withMutation(keyPath: \.menuBarDisplay) {
                _menuBarDisplay = newValue
                defaults.set(newValue.showsNextEvent, forKey: Keys.menuBarShowsNextEvent)
                defaults.set(newValue.showsTitles, forKey: Keys.menuBarShowsEventTitles)
            }
        }
    }

    public var autoCloseEnabled: Bool {
        get { access(keyPath: \.autoCloseEnabled); return _autoCloseEnabled }
        set {
            withMutation(keyPath: \.autoCloseEnabled) {
                _autoCloseEnabled = newValue
                defaults.set(newValue, forKey: Keys.autoCloseEnabled)
            }
        }
    }

    /// How long a full-screen alert stays before it closes itself, in seconds: never less than a minute, stored
    /// or set, since the alert's timer would otherwise close it as it appears.
    public var autoCloseAfter: TimeInterval {
        get { access(keyPath: \.autoCloseAfter); return _autoCloseAfter }
        set {
            withMutation(keyPath: \.autoCloseAfter) {
                _autoCloseAfter = Self.atLeastAMinute(newValue)
                defaults.set(_autoCloseAfter, forKey: Keys.autoCloseAfter)
            }
        }
    }

    private static func atLeastAMinute(_ seconds: TimeInterval) -> TimeInterval {
        max(60, seconds)
    }

    /// A system sound name (from /System/Library/Sounds), or nil for silence.
    public var soundName: String? {
        get { access(keyPath: \.soundName); return _soundName }
        set {
            withMutation(keyPath: \.soundName) {
                _soundName = newValue
                if let newValue { defaults.set(newValue, forKey: Keys.soundName) } else { defaults.removeObject(forKey: Keys.soundName) }
            }
        }
    }

    public var soundRepeats: Bool {
        get { access(keyPath: \.soundRepeats); return _soundRepeats }
        set {
            withMutation(keyPath: \.soundRepeats) {
                _soundRepeats = newValue
                defaults.set(newValue, forKey: Keys.soundRepeats)
            }
        }
    }

    /// nil means the user has never chosen, so every calendar is included.
    public var enabledCalendarIDs: Set<String>? {
        get { access(keyPath: \.enabledCalendarIDs); return _enabledCalendarIDs }
        set {
            withMutation(keyPath: \.enabledCalendarIDs) {
                _enabledCalendarIDs = newValue
                if let newValue {
                    defaults.set(Array(newValue).sorted(), forKey: Keys.enabledCalendarIDs)
                } else {
                    defaults.removeObject(forKey: Keys.enabledCalendarIDs)
                }
            }
        }
    }

    /// What Join! does with events nobody else is on (focus time, reminders you add for yourself).
    /// Show and alert by default, like any other event.
    public var eventsWithoutParticipants: EventVisibility {
        get { access(keyPath: \.eventsWithoutParticipants); return _eventsWithoutParticipants }
        set {
            withMutation(keyPath: \.eventsWithoutParticipants) {
                _eventsWithoutParticipants = newValue
                defaults.set(newValue.rawValue, forKey: Keys.eventsWithoutParticipants)
                defaults.removeObject(forKey: Keys.legacyShowsEventsWithoutParticipants)
            }
        }
    }

    /// How the full-screen alert looks. A look that matches no preset is kept as `customAppearance` too.
    public var appearance: AlertAppearance {
        get { access(keyPath: \.appearance); return _appearance }
        set {
            withMutation(keyPath: \.appearance) {
                _appearance = newValue
                defaults.setJSON(newValue, forKey: Keys.appearance)
            }
            if newValue.matchingPreset == nil, newValue != _customAppearance { customAppearance = newValue }
        }
    }

    /// The look on Appearance's Custom card: the last one that matched no preset. A preset or Restore Defaults
    /// leaves it as it is, so clicking the card brings it back (`applyCustomAppearance`). nil until there's
    /// one, while the card shows a placeholder. Seeded on the first load from a stored look that matches no
    /// preset; a stored one that matches a preset is ignored.
    public var customAppearance: AlertAppearance? {
        get { access(keyPath: \.customAppearance); return _customAppearance }
        set {
            withMutation(keyPath: \.customAppearance) {
                _customAppearance = newValue
                if let newValue {
                    defaults.setJSON(newValue, forKey: Keys.customAppearance)
                } else {
                    defaults.removeObject(forKey: Keys.customAppearance)
                }
            }
        }
    }

    /// What Join! does with events whose titles match `outOfOfficeKeywords`. Show in the list only by
    /// default: striped and muted in the panel's lists, never alerting or driving the menu bar item.
    public var outOfOfficeEvents: EventVisibility {
        get { access(keyPath: \.outOfOfficeEvents); return _outOfOfficeEvents }
        set {
            withMutation(keyPath: \.outOfOfficeEvents) {
                _outOfOfficeEvents = newValue
                defaults.set(newValue.rawValue, forKey: Keys.outOfOfficeEvents)
                defaults.removeObject(forKey: Keys.legacyAlertForOutOfOffice)
                defaults.removeObject(forKey: Keys.legacyShowOutOfOfficeInList)
                defaults.removeObject(forKey: Keys.legacySkipOutOfOffice)
            }
        }
    }

    public var outOfOfficeKeywords: [String] {
        get { access(keyPath: \.outOfOfficeKeywords); return _outOfOfficeKeywords }
        set {
            withMutation(keyPath: \.outOfOfficeKeywords) {
                _outOfOfficeKeywords = newValue
                defaults.set(newValue, forKey: Keys.outOfOfficeKeywords)
            }
        }
    }

    /// When the menu bar's starting-soon pill appears, and its colors.
    public var startingSoonPill: StartingSoonPill {
        get { access(keyPath: \.startingSoonPill); return _startingSoonPill }
        set {
            withMutation(keyPath: \.startingSoonPill) {
                _startingSoonPill = newValue
                defaults.setJSON(newValue, forKey: Keys.startingSoonPill)
            }
        }
    }

    /// The menu bar panel's Today | 7 Days choice, remembered between openings. 7 Days by default, so the
    /// list starts out showing the coming days.
    public var panelListFilter: PanelListFilter {
        get { access(keyPath: \.panelListFilter); return _panelListFilter }
        set {
            withMutation(keyPath: \.panelListFilter) {
                _panelListFilter = newValue
                defaults.set(newValue.rawValue, forKey: Keys.panelListFilter)
            }
        }
    }

    /// The event occurrences dismissed from the menu bar panel, on their own or with all future events of
    /// their series: no full-screen alert, off the menu bar item and the card, listed as dismissed until they
    /// end. Not a setting, so Restore Defaults and the other resets leave it alone; the meeting store prunes
    /// it as events end (`DismissedEvents.pruned`). Empty by default, and when what's stored can't be read.
    public var dismissedEvents: DismissedEvents {
        get { access(keyPath: \.dismissedEvents); return _dismissedEvents }
        set {
            withMutation(keyPath: \.dismissedEvents) {
                _dismissedEvents = newValue
                if newValue.isEmpty {
                    defaults.removeObject(forKey: Keys.dismissedEvents)
                } else {
                    defaults.setJSON(newValue, forKey: Keys.dismissedEvents)
                }
            }
        }
    }

    /// Whether Join! asks GitHub for a newer release once a day. On by default; Check Now works either way.
    public var checksForUpdates: Bool {
        get { access(keyPath: \.checksForUpdates); return _checksForUpdates }
        set {
            withMutation(keyPath: \.checksForUpdates) {
                _checksForUpdates = newValue
                defaults.set(newValue, forKey: Keys.checksForUpdates)
            }
        }
    }

    /// When the last update check succeeded, or nil if none has. Failures aren't stored.
    public var lastUpdateCheck: Date? {
        get { access(keyPath: \.lastUpdateCheck); return _lastUpdateCheck }
        set {
            withMutation(keyPath: \.lastUpdateCheck) {
                _lastUpdateCheck = newValue
                if let newValue { defaults.set(newValue, forKey: Keys.lastUpdateCheck) } else { defaults.removeObject(forKey: Keys.lastUpdateCheck) }
            }
        }
    }

    /// The version the last successful check offered, or nil when it found none. Lets a relaunch show an
    /// offer again without waiting a day. Stored as its "1.1.0" string; one that can't be read loads as nil.
    public var offeredUpdateVersion: AppVersion? {
        get { access(keyPath: \.offeredUpdateVersion); return _offeredUpdateVersion }
        set {
            withMutation(keyPath: \.offeredUpdateVersion) {
                _offeredUpdateVersion = newValue
                if let newValue {
                    defaults.set(newValue.description, forKey: Keys.offeredUpdateVersion)
                } else {
                    defaults.removeObject(forKey: Keys.offeredUpdateVersion)
                }
            }
        }
    }

    /// A release whose install found it needs a newer macOS, so it isn't offered again; nil when there's none.
    public var unsupportedUpdate: UnsupportedUpdate? {
        get { access(keyPath: \.unsupportedUpdate); return _unsupportedUpdate }
        set {
            withMutation(keyPath: \.unsupportedUpdate) {
                _unsupportedUpdate = newValue
                if let newValue {
                    defaults.setJSON(newValue, forKey: Keys.unsupportedUpdate)
                } else {
                    defaults.removeObject(forKey: Keys.unsupportedUpdate)
                }
            }
        }
    }

    public func resetOutOfOfficeKeywords() {
        outOfOfficeKeywords = OutOfOfficeDetector.defaultKeywords
    }

    public func isCalendarEnabled(_ id: String) -> Bool {
        enabledCalendarIDs?.contains(id) ?? true
    }

    /// `allCalendarIDs` is needed the first time, to turn "all calendars" into an explicit set.
    public func setCalendar(_ id: String, enabled: Bool, allCalendarIDs: [String]) {
        var set = enabledCalendarIDs ?? Set(allCalendarIDs)
        if enabled { set.insert(id) } else { set.remove(id) }
        enabledCalendarIDs = set
    }

    /// Appearance's Restore Defaults, disabled while `appearance.isDefault`: the Dark style and its default
    /// colors. Only the look: the Custom card's saved look, the snooze buttons, auto-close and the menu bar
    /// pill stay as they are.
    public func resetAppearance() {
        appearance = .default
    }

    /// The Custom card's click: puts its saved look back. Does nothing while there's none.
    public func applyCustomAppearance() {
        guard let customAppearance else { return }
        appearance = customAppearance
    }
}

private extension UserDefaults {
    /// The value stored as JSON under `key`, or nil when there's none or it can't be read. One that can't be
    /// read is logged with the decoding error, which says which field failed; the error stays private, since
    /// its coding path can hold event ids.
    func decodedJSON<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            logger.error("Couldn't read the stored \(key, privacy: .public); using the default: \(String(describing: error))")
            return nil
        }
    }

    /// Stores `value` as JSON under `key`. If it can't be encoded (a color with a NaN component, say), what's
    /// stored stays as it was and the failure is logged.
    func setJSON(_ value: some Encodable, forKey key: String) {
        do {
            set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            logger.error("Couldn't store \(key, privacy: .public); keeping what was stored: \(String(describing: error))")
        }
    }
}
