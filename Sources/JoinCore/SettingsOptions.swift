import Foundation

/// The choices the Settings pop-ups offer, and the labels they show.
public enum SettingsOptions {
    // MARK: Lead time

    /// Preset lead times, in minutes. Anything else shows as Custom.
    public static let leadTimeMinutes: [Int] = [0, 1, 2, 3, 5, 10]
    public static let customLeadTimeRange: ClosedRange<Int> = 0...120

    public static func isPresetLeadTime(_ leadTime: TimeInterval) -> Bool {
        leadTimeMinutes.contains(wholeMinutes(leadTime))
    }

    public static func leadTimeTitle(minutes: Int) -> String {
        switch minutes {
        case 0: return "When the event starts"
        case 1: return "1 minute before"
        default: return "\(minutes) minutes before"
        }
    }

    // MARK: Snooze

    public static let snoozeMinutes: [Int] = [1, 2, 3, 5, 10, 15, 30, 60]

    /// The snooze list, plus `current` in order when it isn't one of the presets, so a value saved
    /// by an earlier build still shows instead of a blank pop-up.
    public static func snoozeChoices(including current: Int) -> [Int] {
        merging(current, into: snoozeMinutes)
    }

    /// "1 minute", "5 minutes", "1 hour".
    public static func durationTitle(minutes: Int) -> String {
        if minutes >= 60, minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    /// "1 min", "1 hr", as on the alert's buttons.
    public static func shortDurationTitle(minutes: Int) -> String {
        if minutes >= 60, minutes % 60 == 0 {
            return "\(minutes / 60) hr"
        }
        return "\(minutes) min"
    }

    /// What the alert's snooze row offers: both snooze durations, then snoozing until the event.
    public static func alertOffers(snoozeDurations: [TimeInterval]) -> [String] {
        snoozeDurations.map { shortDurationTitle(minutes: wholeMinutes($0)) } + ["At event start"]
    }

    // MARK: Auto-close

    public static let autoCloseMinutes: [Int] = [5, 10, 15, 30, 60]

    /// The pop-up's selection: nil is Never.
    public static func autoCloseSelection(enabled: Bool, after: TimeInterval) -> Int? {
        enabled ? wholeMinutes(after) : nil
    }

    public static func autoCloseChoices(including current: Int?) -> [Int] {
        guard let current else { return autoCloseMinutes }
        return merging(current, into: autoCloseMinutes)
    }

    public static func autoCloseTitle(minutes: Int?) -> String {
        guard let minutes else { return "Never" }
        return "After " + durationTitle(minutes: minutes)
    }

    // MARK: Open at login

    public static let openAtLoginApprovalHint = "Allow Join! in System Settings › General › Login Items to open it at login."
    public static let openAtLoginFixtureNote = "Not available in fixture mode."

    /// Registered but waiting for approval in System Settings still reads as on, so turning the
    /// switch off can withdraw the request.
    public static func opensAtLogin(_ status: LoginItemStatus) -> Bool {
        status == .enabled || status == .requiresApproval
    }

    /// Shown under the switch until the user allows Join! in System Settings.
    public static func openAtLoginHint(_ status: LoginItemStatus) -> String? {
        status == .requiresApproval ? openAtLoginApprovalHint : nil
    }

    // MARK: Window

    /// A fixture run is marked on every pane, so it can't pass for the real app.
    public static func windowTitle(pane: String, isFixture: Bool) -> String {
        isFixture ? pane + " (fixture)" : pane
    }

    // MARK: Calendars

    /// "Updated just now", "Updated 5 minutes ago", …
    public static func updatedLabel(lastRefreshed: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(lastRefreshed)
        if seconds < 60 { return "Updated just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return minutes == 1 ? "Updated 1 minute ago" : "Updated \(minutes) minutes ago" }
        let hours = minutes / 60
        if hours < 24 { return hours == 1 ? "Updated 1 hour ago" : "Updated \(hours) hours ago" }
        let days = hours / 24
        return days == 1 ? "Updated 1 day ago" : "Updated \(days) days ago"
    }

    public static func wholeMinutes(_ seconds: TimeInterval) -> Int {
        Int((seconds / 60).rounded())
    }

    private static func merging(_ value: Int, into list: [Int]) -> [Int] {
        list.contains(value) ? list : (list + [value]).sorted()
    }
}

/// The login item's state as `SMAppService.Status` reports it.
public enum LoginItemStatus: Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

/// Selecting and counting calendars, where a nil selection means every calendar is enabled.
public enum CalendarSelection {
    public static func enabledCount(of ids: [String], in enabled: Set<String>?) -> Int {
        guard let enabled else { return ids.count }
        return ids.filter(enabled.contains).count
    }

    /// The new selection after turning `ids` on or off. `allCalendarIDs` turns "every calendar"
    /// into an explicit set the first time.
    public static func setting(_ ids: [String], enabled: Bool, in current: Set<String>?, allCalendarIDs: [String]) -> Set<String> {
        var selection = current ?? Set(allCalendarIDs)
        if enabled {
            selection.formUnion(ids)
        } else {
            selection.subtract(ids)
        }
        return selection
    }
}

/// Editing the out-of-office keywords as tokens.
public enum KeywordList {
    /// Adds a trimmed keyword unless it is empty or already present, ignoring case.
    public static func adding(_ text: String, to keywords: [String]) -> [String] {
        let keyword = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty,
              !keywords.contains(where: { $0.caseInsensitiveCompare(keyword) == .orderedSame })
        else { return keywords }
        return keywords + [keyword]
    }

    /// A comma ends a keyword, like Return: everything before the last comma becomes keywords and
    /// the rest stays in the field.
    public static func splittingDraft(_ draft: String, into keywords: [String]) -> (keywords: [String], draft: String) {
        guard draft.contains(",") else { return (keywords, draft) }
        var parts = draft.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        let remainder = parts.removeLast()
        let updated = parts.reduce(keywords) { adding($1, to: $0) }
        return (updated, String(remainder.drop(while: \.isWhitespace)))
    }
}
