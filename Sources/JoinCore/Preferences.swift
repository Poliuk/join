import Foundation
import Observation

/// All user-configurable settings. One owner, persisted to UserDefaults on every change,
/// observable by SwiftUI through the Observation framework.
@MainActor
@Observable
public final class Preferences {
    public enum Keys {
        public static let leadTime = "leadTime"
        public static let snoozeDurations = "snoozeDurations"
        public static let alertScreens = "alertScreens"
        /// Earlier builds stored a Bool here; true maps to `.all`, false to `.main`.
        public static let legacyShowOnAllScreens = "showOnAllScreens"
        public static let menuBarShowsEventTitles = "menuBarShowsEventTitles"
        public static let autoCloseEnabled = "autoCloseEnabled"
        public static let autoCloseAfter = "autoCloseAfter"
        public static let soundName = "soundName"
        public static let soundRepeats = "soundRepeats"
        public static let enabledCalendarIDs = "enabledCalendarIDs"
        public static let showsEventsWithoutParticipants = "showsEventsWithoutParticipants"
        public static let menuBarShowsNextEvent = "menuBarShowsNextEvent"
        public static let appearance = "appearance"
        public static let alertForOutOfOffice = "alertForOutOfOffice"
        /// Earlier builds stored the inverse of `alertForOutOfOffice` under this key.
        public static let legacySkipOutOfOffice = "skipOutOfOffice"
        public static let outOfOfficeKeywords = "outOfOfficeKeywords"
        public static let showOutOfOfficeInList = "showOutOfOfficeInList"
        public static let startingSoonPill = "startingSoonPill"
        public static let panelListFilter = "panelListFilter"
        public static let checksForUpdates = "checksForUpdates"
        public static let lastUpdateCheck = "lastUpdateCheck"
        public static let offeredUpdateVersion = "offeredUpdateVersion"
        public static let unsupportedUpdate = "unsupportedUpdate"
    }

    public static let defaultLeadTime: TimeInterval = 3 * 60
    public static let defaultSnoozeDurations: [TimeInterval] = [60, 5 * 60]
    public static let defaultAutoCloseAfter: TimeInterval = 15 * 60

    private let defaults: UserDefaults

    @ObservationIgnored private var _leadTime: TimeInterval
    @ObservationIgnored private var _snoozeDurations: [TimeInterval]
    @ObservationIgnored private var _alertScreens: AlertScreens
    @ObservationIgnored private var _menuBarShowsEventTitles: Bool
    @ObservationIgnored private var _autoCloseEnabled: Bool
    @ObservationIgnored private var _autoCloseAfter: TimeInterval
    @ObservationIgnored private var _soundName: String?
    @ObservationIgnored private var _soundRepeats: Bool
    @ObservationIgnored private var _enabledCalendarIDs: Set<String>?
    @ObservationIgnored private var _showsEventsWithoutParticipants: Bool
    @ObservationIgnored private var _menuBarShowsNextEvent: Bool
    @ObservationIgnored private var _appearance: AlertAppearance
    @ObservationIgnored private var _alertForOutOfOffice: Bool
    @ObservationIgnored private var _outOfOfficeKeywords: [String]
    @ObservationIgnored private var _showOutOfOfficeInList: Bool
    @ObservationIgnored private var _startingSoonPill: StartingSoonPill
    @ObservationIgnored private var _panelListFilter: PanelListFilter
    @ObservationIgnored private var _checksForUpdates: Bool
    @ObservationIgnored private var _lastUpdateCheck: Date?
    @ObservationIgnored private var _offeredUpdateVersion: String?
    @ObservationIgnored private var _unsupportedUpdate: UnsupportedUpdate?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        _leadTime = Self.wholeMinutes(defaults.object(forKey: Keys.leadTime) as? TimeInterval ?? Self.defaultLeadTime)
        let storedSnooze = defaults.array(forKey: Keys.snoozeDurations) as? [TimeInterval]
        _snoozeDurations = (storedSnooze?.count == 2 ? storedSnooze : nil) ?? Self.defaultSnoozeDurations
        if let raw = defaults.string(forKey: Keys.alertScreens), let stored = AlertScreens(rawValue: raw) {
            _alertScreens = stored
        } else if let legacy = defaults.object(forKey: Keys.legacyShowOnAllScreens) as? Bool {
            _alertScreens = legacy ? .all : .main
        } else {
            _alertScreens = .all
        }
        _menuBarShowsEventTitles = defaults.object(forKey: Keys.menuBarShowsEventTitles) as? Bool ?? false
        _autoCloseEnabled = defaults.object(forKey: Keys.autoCloseEnabled) as? Bool ?? true
        _autoCloseAfter = defaults.object(forKey: Keys.autoCloseAfter) as? TimeInterval ?? Self.defaultAutoCloseAfter
        _soundName = defaults.string(forKey: Keys.soundName)
        _soundRepeats = defaults.object(forKey: Keys.soundRepeats) as? Bool ?? false
        _enabledCalendarIDs = (defaults.array(forKey: Keys.enabledCalendarIDs) as? [String]).map(Set.init)
        _showsEventsWithoutParticipants = defaults.object(forKey: Keys.showsEventsWithoutParticipants) as? Bool ?? true
        _menuBarShowsNextEvent = defaults.object(forKey: Keys.menuBarShowsNextEvent) as? Bool ?? true
        _appearance = defaults.data(forKey: Keys.appearance)
            .flatMap { try? JSONDecoder().decode(AlertAppearance.self, from: $0) } ?? .default
        if let stored = defaults.object(forKey: Keys.alertForOutOfOffice) as? Bool {
            _alertForOutOfOffice = stored
        } else if let legacySkip = defaults.object(forKey: Keys.legacySkipOutOfOffice) as? Bool {
            _alertForOutOfOffice = !legacySkip
        } else {
            _alertForOutOfOffice = false
        }
        _outOfOfficeKeywords = defaults.array(forKey: Keys.outOfOfficeKeywords) as? [String] ?? OutOfOfficeDetector.defaultKeywords
        _showOutOfOfficeInList = defaults.object(forKey: Keys.showOutOfOfficeInList) as? Bool ?? true
        _startingSoonPill = defaults.data(forKey: Keys.startingSoonPill)
            .flatMap { try? JSONDecoder().decode(StartingSoonPill.self, from: $0) } ?? .default
        _panelListFilter = defaults.string(forKey: Keys.panelListFilter).flatMap(PanelListFilter.init(rawValue:)) ?? .week
        _checksForUpdates = defaults.object(forKey: Keys.checksForUpdates) as? Bool ?? true
        _lastUpdateCheck = defaults.object(forKey: Keys.lastUpdateCheck) as? Date
        _offeredUpdateVersion = defaults.string(forKey: Keys.offeredUpdateVersion)
        _unsupportedUpdate = defaults.data(forKey: Keys.unsupportedUpdate)
            .flatMap { try? JSONDecoder().decode(UnsupportedUpdate.self, from: $0) }
    }

    /// Seconds before the meeting start at which the alert fires, always a whole number of minutes.
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

    /// Exactly two entries, in seconds.
    public var snoozeDurations: [TimeInterval] {
        get { access(keyPath: \.snoozeDurations); return _snoozeDurations }
        set {
            guard newValue.count == 2 else { return }
            withMutation(keyPath: \.snoozeDurations) {
                _snoozeDurations = newValue
                defaults.set(newValue, forKey: Keys.snoozeDurations)
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

    /// Whether the menu bar item starts with the event's title (in place of "Next"). Off by default.
    /// Set through `menuBarDisplay` from Settings.
    public var menuBarShowsEventTitles: Bool {
        get { access(keyPath: \.menuBarShowsEventTitles); return _menuBarShowsEventTitles }
        set {
            withMutation(keyPath: \.menuBarShowsEventTitles) {
                _menuBarShowsEventTitles = newValue
                defaults.set(newValue, forKey: Keys.menuBarShowsEventTitles)
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

    public var autoCloseAfter: TimeInterval {
        get { access(keyPath: \.autoCloseAfter); return _autoCloseAfter }
        set {
            withMutation(keyPath: \.autoCloseAfter) {
                _autoCloseAfter = max(60, newValue)
                defaults.set(_autoCloseAfter, forKey: Keys.autoCloseAfter)
            }
        }
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

    /// Whether events nobody else is on (focus time, reminders you add for yourself) appear at all. On by
    /// default; when off, they're left out of the panel, the menu bar and alerts, like an unchecked calendar.
    public var showsEventsWithoutParticipants: Bool {
        get { access(keyPath: \.showsEventsWithoutParticipants); return _showsEventsWithoutParticipants }
        set {
            withMutation(keyPath: \.showsEventsWithoutParticipants) {
                _showsEventsWithoutParticipants = newValue
                defaults.set(newValue, forKey: Keys.showsEventsWithoutParticipants)
            }
        }
    }

    public var menuBarShowsNextEvent: Bool {
        get { access(keyPath: \.menuBarShowsNextEvent); return _menuBarShowsNextEvent }
        set {
            withMutation(keyPath: \.menuBarShowsNextEvent) {
                _menuBarShowsNextEvent = newValue
                defaults.set(newValue, forKey: Keys.menuBarShowsNextEvent)
            }
        }
    }

    public var appearance: AlertAppearance {
        get { access(keyPath: \.appearance); return _appearance }
        set {
            withMutation(keyPath: \.appearance) {
                _appearance = newValue
                defaults.set(try? JSONEncoder().encode(newValue), forKey: Keys.appearance)
            }
        }
    }

    /// When off (the default), events that look like out-of-office blocks never alert and are left
    /// out of the menu bar item. They still appear, dimmed, in the panel's lists unless
    /// `showOutOfOfficeInList` is off.
    public var alertForOutOfOffice: Bool {
        get { access(keyPath: \.alertForOutOfOffice); return _alertForOutOfOffice }
        set {
            withMutation(keyPath: \.alertForOutOfOffice) {
                _alertForOutOfOffice = newValue
                defaults.set(newValue, forKey: Keys.alertForOutOfOffice)
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

    /// Whether out-of-office events appear (striped and muted) in the menu bar panel's lists. On by default.
    public var showOutOfOfficeInList: Bool {
        get { access(keyPath: \.showOutOfOfficeInList); return _showOutOfOfficeInList }
        set {
            withMutation(keyPath: \.showOutOfOfficeInList) {
                _showOutOfOfficeInList = newValue
                defaults.set(newValue, forKey: Keys.showOutOfOfficeInList)
            }
        }
    }

    /// When the menu bar's starting-soon pill appears, and its colors.
    public var startingSoonPill: StartingSoonPill {
        get { access(keyPath: \.startingSoonPill); return _startingSoonPill }
        set {
            withMutation(keyPath: \.startingSoonPill) {
                _startingSoonPill = newValue
                defaults.set(try? JSONEncoder().encode(newValue), forKey: Keys.startingSoonPill)
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

    /// The version the last successful check offered, "1.1.0", or nil when it found none. Lets a relaunch
    /// show an offer again without waiting a day.
    public var offeredUpdateVersion: String? {
        get { access(keyPath: \.offeredUpdateVersion); return _offeredUpdateVersion }
        set {
            withMutation(keyPath: \.offeredUpdateVersion) {
                _offeredUpdateVersion = newValue
                if let newValue { defaults.set(newValue, forKey: Keys.offeredUpdateVersion) } else { defaults.removeObject(forKey: Keys.offeredUpdateVersion) }
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
                    defaults.set(try? JSONEncoder().encode(newValue), forKey: Keys.unsupportedUpdate)
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

    public func resetAppearance() {
        appearance = .default
    }
}
