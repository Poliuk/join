import Foundation

/// The choices the Settings pop-ups offer, and the labels they show.
public enum SettingsOptions {
    // MARK: Full-screen alert

    /// Preset lead times, in minutes. Anything else, including 2 and 10 from earlier builds, shows as
    /// Custom… while full-screen alerts are on.
    public static let leadTimeMinutes: [Int] = [0, 1, 3, 5]
    public static let customLeadTimeRange: ClosedRange<Int> = 0...120

    /// Notify me's presets and Custom… range: exactly Alert me's, worded the same (`leadTimeTitle`), with the
    /// same Never (`leadTimeNeverTitle`).
    public static let notificationLeadTimeMinutes: [Int] = leadTimeMinutes
    public static let customNotificationLeadTimeRange: ClosedRange<Int> = customLeadTimeRange

    public static func leadTimeTitle(minutes: Int) -> String {
        switch minutes {
        case 0: return "When the event starts"
        case 1: return "1 minute before"
        default: return "\(minutes) minutes before"
        }
    }

    /// Alert me's and Notify me's item after the presets, before Custom…: it turns that kind of alert off.
    /// Which item shows, and what picking one changes, is `MinutesChoice`.
    public static let leadTimeNeverTitle = "Never"

    // MARK: Snooze

    /// Preset snooze durations, in minutes. Anything else, including values saved by earlier builds
    /// (15, 30, 60), shows as Custom.
    public static let snoozeMinutes: [Int] = [1, 3, 5, 10]
    public static let customSnoozeRange: ClosedRange<Int> = 1...120

    /// "1 minute", "5 minutes", "1 hour".
    public static func durationTitle(minutes: Int) -> String {
        if minutes >= 60, minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    /// "1 min", "1 hr", as on the alert's buttons.
    static func shortDurationTitle(minutes: Int) -> String {
        if minutes >= 60, minutes % 60 == 0 {
            return "\(minutes / 60) hr"
        }
        return "\(minutes) min"
    }

    // MARK: Alerts pane

    /// The pane for both kinds of alert, which was Full-Screen Alert until 1.3.0: "alerts" covers the
    /// full-screen alert and the notification.
    public static let alertsPaneTitle = "Alerts"

    /// Its three boxes, top to bottom: each kind with its own time or Never, then the snooze durations they
    /// share.
    public static let fullScreenAlertSectionTitle = "Full-screen alert"
    public static let notificationSectionTitle = "Notification"
    public static let snoozeSectionTitle = "Snooze"

    /// The Full-screen alert box's first row: the full-screen alert's time or Never.
    public static let alertMeTitle = "Alert me"
    /// What VoiceOver calls Alert me's custom minutes field and stepper, named for its row since Notify me's
    /// can show on the pane too.
    public static let alertMeFieldLabel = "\(alertMeTitle), minutes before the event"

    /// The second row of the Full-screen alert box and of the Notification box: which screens that kind comes
    /// up on (`AlertScreens`), each kind with its own choice. Dimmed while its kind's time is Never.
    public static let showOnTitle = "Show on"

    /// The last row of the Full-screen alert box and of the Notification box, each kind with its own time,
    /// counted from when it appears; the same items and wording in both (`autoCloseChoices`,
    /// `autoCloseTitle`). Dimmed while its kind's time is Never.
    public static let autoCloseRowTitle = "Close automatically"

    /// The Notification box's first row: its own time or Never, set independently of Alert me.
    public static let notifyMeTitle = "Notify me"
    /// Notify me's help tag. Join! draws the notification itself since 2026-10-19, with a Join button and a menu
    /// (`NotificationCard`), rather than posting a macOS notification.
    public static let notifyMeHelp = "Shows a notification at the top right of the screen with a Join button and a menu to snooze or dismiss it."
    /// What VoiceOver calls Notify me's custom minutes field and stepper.
    public static let notifyMeFieldLabel = "\(notifyMeTitle), minutes before the event"

    /// The Notification box's switch: the user's alert sound, once, as a card appears or comes back from a
    /// snooze, or none. Dimmed while Notify me is Never.
    public static let playSoundTitle = "Play sound"
    public static let playSoundHelp = "Plays your alert sound from System Settings › Sound when the notification appears."

    /// Under the Notification box, beside Test Notification: Join! can't tell when a Focus is on or the screen
    /// is shared, so the card shows during both, like the full-screen alert, and the pause is how to keep it away.
    public static let notificationFootnote = "Join! shows this notification itself, so it also comes up during a Focus and while you share your screen. To keep it away, pause alerts from the menu bar."

    /// The Snooze box's rows, the two times both kinds share. "First snooze button" and "Second snooze button"
    /// until 2026-10-19: the notification offers them in a menu, not as buttons.
    public static let firstSnoozeTitle = "First snooze"
    public static let secondSnoozeTitle = "Second snooze"
    /// What VoiceOver calls each row's custom minutes field and stepper.
    public static let firstSnoozeFieldLabel = "\(firstSnoozeTitle), minutes"
    public static let secondSnoozeFieldLabel = "\(secondSnoozeTitle), minutes"

    /// Under the Snooze box: that both kinds use these two times, each in its own way, then the snooze both add
    /// after them. The user asked for the section's explanation to be clearer (2026-10-19).
    public static let snoozeFootnote = "The full-screen alert's snooze buttons and the notification's menu both offer these two times, then \(AlertCountdown.snoozeUntilStartLabel)."

    // MARK: Test buttons

    /// Under the Full-screen alert box at its right, and under Appearance's preview box at its right: shows
    /// the full-screen alert for the demo event (`DemoEvent`). Show Demo until 2026-10-19, when the user found
    /// the demo buttons' labels confusing.
    public static let testFullScreenAlertTitle = "Test Full-Screen Alert"
    /// Its help tags, while it works and while a real full-screen alert is on screen.
    public static let testFullScreenAlertHelp = "Shows a test full-screen alert with a sample event. Press Esc to close it."
    public static let testFullScreenAlertUnavailableHelp = "Close the current full-screen alert first."

    /// Under the Notification box at its right, beside the footnote: shows the demo event's card
    /// (`NotificationCard.test`), replacing one already up. Always enabled: it works while alerts are paused,
    /// while Notify me is Never and in a fixture run, as Test Full-Screen Alert does.
    public static let testNotificationTitle = "Test Notification"
    public static let testNotificationHelp = "Shows a test notification with a sample event."

    // MARK: Appearance pane

    /// The box of the alert's colors, under Style.
    public static let colorsSectionTitle = "Colors"

    /// Under the preview while Alert me is Never, which stops real full-screen alerts only, whatever Notify me
    /// says: the pane is the full-screen alert's look, and notifications have none to set.
    public static let alertMeNeverNote = "\(alertMeTitle) is set to \(leadTimeNeverTitle) in \(alertsPaneTitle). \(testFullScreenAlertTitle) still works."

    /// Restore Defaults' help tag, at the bottom right of the pane: it restores the look only.
    public static let restoreAppearanceHelp = "Goes back to the Dark style. Your own style stays on the Custom card."

    // MARK: Menu bar

    /// The General pane's section for the menu bar item and its starting-soon pill.
    public static let menuBarSectionTitle = "Menu bar"
    /// The section's first row, a pop-up of `MenuBarDisplay` choices.
    public static let menuBarShowsTitle = "Shows"

    // MARK: Starting soon

    /// The Menu bar section's row with the pill's preview and when it appears.
    public static let startingSoonRowTitle = "Starting soon"
    public static let startingSoonHelp = "The menu bar shows the event like this from then on. The panel highlights it at the same time."
    /// VoiceOver names for the row's custom minutes field and its preview.
    public static let startingSoonFieldLabel = "Minutes before the event"
    public static let menuBarPreviewLabel = "Preview of the menu bar before an event"

    /// The pill's color row (`StartingSoonPill.colorChoice`), a sibling of Starting soon, and the VoiceOver
    /// names of its pop-up and well, and of the legacy Text row's.
    public static let menuBarColorTitle = "Color"
    public static let menuBarColorAccessibilityTitle = "Menu bar fill"
    public static let menuBarColorWellLabel = "Menu bar fill color"
    public static let menuBarTextAccessibilityTitle = "Menu bar text"
    public static let menuBarTextWellLabel = "Menu bar text color"

    /// How long before a meeting the menu bar pill appears, in minutes. Anything else shows as Custom,
    /// within `StartingSoonPill.minuteRange`.
    public static let startingSoonMinutes: [Int] = [1, 3, 5, 10]

    /// "1 minute before", "5 minutes before".
    public static func startingSoonTitle(minutes: Int) -> String {
        minutes == 1 ? "1 minute before" : "\(minutes) minutes before"
    }

    /// After a custom number of minutes: "minute before", "minutes before".
    public static func minutesBeforeUnit(_ minutes: Int) -> String {
        minutes == 1 ? "minute before" : "minutes before"
    }

    /// After a custom duration: "minute", "minutes".
    public static func minutesUnit(_ minutes: Int) -> String {
        minutes == 1 ? "minute" : "minutes"
    }

    // MARK: Auto-close

    static let autoCloseMinutes: [Int] = [5, 10, 15, 30, 60]

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

    static let openAtLoginApprovalHint = "Allow Join! in System Settings › General › Login Items to open it at login."
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

    // MARK: Events

    /// The General pane's Events section: a pop-up of `EventVisibility` choices for each kind of event,
    /// then the out-of-office keywords and the footnote under them.
    public static let eventsSectionTitle = "Events"
    public static let eventsWithoutParticipantsTitle = "Events with no participants"
    public static let outOfOfficeEventsTitle = "Out-of-office events"
    public static let outOfOfficeKeywordsTitle = "Out-of-office keywords"
    public static let eventsFootnote = "An event counts as out of office when its title contains any of these words. Press Return to add one. Only Show and alert lets an event alert, take the menu bar or sit at the top of the panel. When an event is both kinds, the choice that shows less wins."

    // MARK: Calendars

    /// The Calendars pane's orange line while every calendar is unchecked: no alerts of either kind.
    public static let noCalendarsWarning = "No calendars selected: you won't get any alerts."

    /// How many calendars are checked: the pane's total at the top, and each account's under its box ("2 of 2"
    /// beside its heading until 2026-10-19, when it moved under the box and needed the word).
    public static func calendarsSelected(_ selected: Int, of total: Int) -> String {
        "\(selected) of \(total) selected"
    }

    /// "Updated just now", "Updated 5 minutes ago", …
    public static func updatedLabel(lastRefreshed: Date, now: Date) -> String {
        "Updated " + relativeTime(since: lastRefreshed, now: now)
    }

    /// "just now", "5 minutes ago", "1 hour ago", "2 days ago", rounding down. A time in the future
    /// (the clock moved back) reads as just now.
    static func relativeTime(since date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago" }
        let hours = minutes / 60
        if hours < 24 { return hours == 1 ? "1 hour ago" : "\(hours) hours ago" }
        let days = hours / 24
        return days == 1 ? "1 day ago" : "\(days) days ago"
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
