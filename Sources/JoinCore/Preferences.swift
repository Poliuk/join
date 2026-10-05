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
        public static let showOnAllScreens = "showOnAllScreens"
        public static let autoCloseEnabled = "autoCloseEnabled"
        public static let autoCloseAfter = "autoCloseAfter"
        public static let soundName = "soundName"
        public static let soundRepeats = "soundRepeats"
        public static let enabledCalendarIDs = "enabledCalendarIDs"
        public static let menuBarShowsNextEvent = "menuBarShowsNextEvent"
        public static let appearance = "appearance"
    }

    public static let defaultLeadTime: TimeInterval = 3 * 60
    public static let defaultSnoozeDurations: [TimeInterval] = [60, 5 * 60]
    public static let defaultAutoCloseAfter: TimeInterval = 15 * 60

    private let defaults: UserDefaults

    @ObservationIgnored private var _leadTime: TimeInterval
    @ObservationIgnored private var _snoozeDurations: [TimeInterval]
    @ObservationIgnored private var _showOnAllScreens: Bool
    @ObservationIgnored private var _autoCloseEnabled: Bool
    @ObservationIgnored private var _autoCloseAfter: TimeInterval
    @ObservationIgnored private var _soundName: String?
    @ObservationIgnored private var _soundRepeats: Bool
    @ObservationIgnored private var _enabledCalendarIDs: Set<String>?
    @ObservationIgnored private var _menuBarShowsNextEvent: Bool
    @ObservationIgnored private var _appearance: AlertAppearance

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        _leadTime = defaults.object(forKey: Keys.leadTime) as? TimeInterval ?? Self.defaultLeadTime
        let storedSnooze = defaults.array(forKey: Keys.snoozeDurations) as? [TimeInterval]
        _snoozeDurations = (storedSnooze?.count == 2 ? storedSnooze : nil) ?? Self.defaultSnoozeDurations
        _showOnAllScreens = defaults.object(forKey: Keys.showOnAllScreens) as? Bool ?? true
        _autoCloseEnabled = defaults.object(forKey: Keys.autoCloseEnabled) as? Bool ?? true
        _autoCloseAfter = defaults.object(forKey: Keys.autoCloseAfter) as? TimeInterval ?? Self.defaultAutoCloseAfter
        _soundName = defaults.string(forKey: Keys.soundName)
        _soundRepeats = defaults.object(forKey: Keys.soundRepeats) as? Bool ?? false
        _enabledCalendarIDs = (defaults.array(forKey: Keys.enabledCalendarIDs) as? [String]).map(Set.init)
        _menuBarShowsNextEvent = defaults.object(forKey: Keys.menuBarShowsNextEvent) as? Bool ?? true
        _appearance = defaults.data(forKey: Keys.appearance)
            .flatMap { try? JSONDecoder().decode(AlertAppearance.self, from: $0) } ?? .default
    }

    /// Seconds before the meeting start at which the alert fires.
    public var leadTime: TimeInterval {
        get { access(keyPath: \.leadTime); return _leadTime }
        set {
            withMutation(keyPath: \.leadTime) {
                _leadTime = max(0, newValue)
                defaults.set(_leadTime, forKey: Keys.leadTime)
            }
        }
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

    public var showOnAllScreens: Bool {
        get { access(keyPath: \.showOnAllScreens); return _showOnAllScreens }
        set {
            withMutation(keyPath: \.showOnAllScreens) {
                _showOnAllScreens = newValue
                defaults.set(newValue, forKey: Keys.showOnAllScreens)
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
