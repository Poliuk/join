import Foundation
import Testing
@testable import JoinCore

struct SettingsOptionsTests {
    /// Text the user sees, beside what it must say.
    struct Copy: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let actual: String?
        let expected: String?

        init(_ name: String, _ actual: String?, _ expected: String?) {
            testDescription = name
            self.actual = actual
            self.expected = expected
        }
    }

    // MARK: Pop-ups

    /// A minutes pop-up: its presets and the range of its Custom… field, beside the ones the user chose, and the
    /// defaults it must offer as presets.
    struct MinutesPopUp: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let presets: [Int]
        let expectedPresets: [Int]
        let range: ClosedRange<Int>
        let expectedRange: ClosedRange<Int>
        let defaults: [Int]
    }

    static let popUps: [MinutesPopUp] = [
        MinutesPopUp(
            testDescription: "Alert me",
            presets: SettingsOptions.leadTimeMinutes, expectedPresets: [0, 1, 3, 5],
            range: SettingsOptions.customLeadTimeRange, expectedRange: 0...120,
            defaults: [SettingsOptions.wholeMinutes(Preferences.defaultLeadTime)]
        ),
        // Exactly Alert me's presets, with the 5 minutes Custom… keeps while it is Never.
        MinutesPopUp(
            testDescription: "Notify me",
            presets: SettingsOptions.notificationLeadTimeMinutes, expectedPresets: [0, 1, 3, 5],
            range: SettingsOptions.customNotificationLeadTimeRange, expectedRange: 0...120,
            defaults: [SettingsOptions.wholeMinutes(Preferences.defaultNotificationLeadTime)]
        ),
        MinutesPopUp(
            testDescription: "Snooze",
            presets: SettingsOptions.snoozeMinutes, expectedPresets: [1, 3, 5, 10],
            range: SettingsOptions.customSnoozeRange, expectedRange: 1...120,
            defaults: Preferences.defaultSnoozeDurations.all.map(SettingsOptions.wholeMinutes)
        ),
        MinutesPopUp(
            testDescription: "Starting soon",
            presets: SettingsOptions.startingSoonMinutes, expectedPresets: [1, 3, 5, 10],
            range: StartingSoonPill.minuteRange, expectedRange: 1...60,
            defaults: [StartingSoonPill.default.minutes]
        ),
    ]

    /// Every default is a preset, and every preset fits the Custom… field.
    @Test(arguments: popUps)
    func popUpPresets(_ popUp: MinutesPopUp) {
        #expect(popUp.presets == popUp.expectedPresets)
        #expect(popUp.range == popUp.expectedRange)
        #expect(popUp.defaults.allSatisfy(popUp.presets.contains), "the defaults are presets")
        #expect(popUp.presets.allSatisfy(popUp.range.contains), "the presets fit the Custom… field")
    }

    static let phrases: [Copy] = [
        Copy("Alert me at 0", SettingsOptions.leadTimeTitle(minutes: 0), "When the event starts"),
        Copy("Alert me at 1", SettingsOptions.leadTimeTitle(minutes: 1), "1 minute before"),
        Copy("Alert me at 3", SettingsOptions.leadTimeTitle(minutes: 3), "3 minutes before"),
        Copy("Alert me at 5", SettingsOptions.leadTimeTitle(minutes: 5), "5 minutes before"),
        Copy("Starting soon at 1", SettingsOptions.startingSoonTitle(minutes: 1), "1 minute before"),
        Copy("Starting soon at 5", SettingsOptions.startingSoonTitle(minutes: 5), "5 minutes before"),
        Copy("Custom… unit before, 1", SettingsOptions.minutesBeforeUnit(1), "minute before"),
        Copy("Custom… unit before, 7", SettingsOptions.minutesBeforeUnit(7), "minutes before"),
        Copy("Custom… unit, 1", SettingsOptions.minutesUnit(1), "minute"),
        Copy("Custom… unit, 45", SettingsOptions.minutesUnit(45), "minutes"),
        // Hours only at whole hours, so 90 stays minutes.
        Copy("duration of 1 min", SettingsOptions.durationTitle(minutes: 1), "1 minute"),
        Copy("duration of 5 min", SettingsOptions.durationTitle(minutes: 5), "5 minutes"),
        Copy("duration of 60 min", SettingsOptions.durationTitle(minutes: 60), "1 hour"),
        Copy("duration of 90 min", SettingsOptions.durationTitle(minutes: 90), "90 minutes"),
        Copy("duration of 120 min", SettingsOptions.durationTitle(minutes: 120), "2 hours"),
        Copy("short duration of 1 min", SettingsOptions.shortDurationTitle(minutes: 1), "1 min"),
        Copy("short duration of 5 min", SettingsOptions.shortDurationTitle(minutes: 5), "5 min"),
        Copy("short duration of 60 min", SettingsOptions.shortDurationTitle(minutes: 60), "1 hr"),
        Copy("short duration of 90 min", SettingsOptions.shortDurationTitle(minutes: 90), "90 min"),
        Copy("short duration of 120 min", SettingsOptions.shortDurationTitle(minutes: 120), "2 hr"),
    ]

    @Test(arguments: phrases)
    func minutePhrases(_ phrase: Copy) {
        #expect(phrase.actual == phrase.expected)
    }

    @Test func autoCloseMapsNeverAndMinutes() {
        #expect(SettingsOptions.autoCloseSelection(enabled: false, after: 900) == nil)
        #expect(SettingsOptions.autoCloseSelection(enabled: true, after: 900) == 15)
        #expect(SettingsOptions.autoCloseChoices(including: nil) == [5, 10, 15, 30, 60])
        #expect(SettingsOptions.autoCloseChoices(including: 15) == [5, 10, 15, 30, 60])
        #expect(SettingsOptions.autoCloseChoices(including: 20) == [5, 10, 15, 20, 30, 60])
        #expect(SettingsOptions.autoCloseTitle(minutes: nil) == "Never")
        #expect(SettingsOptions.autoCloseTitle(minutes: 5) == "After 5 minutes")
        #expect(SettingsOptions.autoCloseTitle(minutes: 60) == "After 1 hour")
    }

    /// The Notification box's Close automatically offers the full-screen alert's items, with its own default
    /// of 10 minutes selected, and shows a stored custom value as the full-screen row does.
    @Test func theNotificationsCloseAutomatically() {
        let preset = SettingsOptions.autoCloseSelection(enabled: true, after: Preferences.defaultNotificationAutoCloseAfter)
        #expect(preset == 10)
        #expect(SettingsOptions.autoCloseTitle(minutes: preset) == "After 10 minutes")
        #expect(SettingsOptions.autoCloseChoices(including: preset) == [5, 10, 15, 30, 60])
        #expect(SettingsOptions.autoCloseChoices(including: 45) == [5, 10, 15, 30, 45, 60])
        #expect(SettingsOptions.autoCloseTitle(minutes: 45) == "After 45 minutes")
        #expect(SettingsOptions.autoCloseSelection(enabled: false, after: Preferences.defaultNotificationAutoCloseAfter) == nil)
    }

    /// Waiting for approval in System Settings reads as on, so turning the switch off withdraws the request,
    /// and the hint stays until the user allows it.
    @Test(arguments: [
        (LoginItemStatus.notRegistered, false, nil),
        (.notFound, false, nil),
        (.requiresApproval, true, "Allow Join! in System Settings › General › Login Items to open it at login."),
        (.enabled, true, nil),
    ] as [(LoginItemStatus, Bool, String?)])
    func openAtLoginFollowsTheStatus(_ status: LoginItemStatus, isOn: Bool, hint: String?) {
        #expect(SettingsOptions.opensAtLogin(status) == isOn)
        #expect(SettingsOptions.openAtLoginHint(status) == hint)
    }

    // MARK: Copy

    static let copy: [Copy] = [
        Copy("Alert me's Never", SettingsOptions.leadTimeNeverTitle, "Never"),
        Copy("Menu bar section", SettingsOptions.menuBarSectionTitle, "Menu bar"),
        Copy("Menu bar's Shows row", SettingsOptions.menuBarShowsTitle, "Shows"),
        Copy("Starting soon row", SettingsOptions.startingSoonRowTitle, "Starting soon"),
        Copy(
            "Starting soon's help tag",
            SettingsOptions.startingSoonHelp,
            "The menu bar shows the event like this from then on. The panel highlights it at the same time."
        ),
        Copy("menu bar Color row", SettingsOptions.menuBarColorTitle, "Color"),
        Copy("Alerts pane", SettingsOptions.alertsPaneTitle, "Alerts"),
        Copy("Full-screen alert box", SettingsOptions.fullScreenAlertSectionTitle, "Full-screen alert"),
        Copy("Notification box", SettingsOptions.notificationSectionTitle, "Notification"),
        Copy("Snooze box", SettingsOptions.snoozeSectionTitle, "Snooze"),
        Copy("Alert me row", SettingsOptions.alertMeTitle, "Alert me"),
        // Both custom fields can show on the pane at once, so VoiceOver names each for its row.
        Copy("Alert me's custom field", SettingsOptions.alertMeFieldLabel, "Alert me, minutes before the event"),
        // Both boxes have these two rows, each kind with its own value.
        Copy("Show on row", SettingsOptions.showOnTitle, "Show on"),
        Copy("auto-close row", SettingsOptions.autoCloseRowTitle, "Close automatically"),
        Copy("Notify me row", SettingsOptions.notifyMeTitle, "Notify me"),
        // Join! draws the notification itself, with a Join button and a menu (2026-10-19).
        Copy("Notify me's help tag", SettingsOptions.notifyMeHelp,
             "Shows a notification at the top right of the screen with a Join button and a menu to snooze or dismiss it."),
        Copy("Notify me's custom field", SettingsOptions.notifyMeFieldLabel, "Notify me, minutes before the event"),
        Copy("Play sound row", SettingsOptions.playSoundTitle, "Play sound"),
        Copy("Play sound's help tag", SettingsOptions.playSoundHelp,
             "Plays your alert sound from System Settings › Sound when the notification appears."),
        // Nothing Join! shows follows a Focus or screen sharing; the pause keeps it away (2026-10-19).
        Copy(
            "Notification footnote",
            SettingsOptions.notificationFootnote,
            "Join! shows this notification itself, so it also comes up during a Focus and while you share your screen. To keep it away, pause alerts from the menu bar."
        ),
        Copy("Test Notification", SettingsOptions.testNotificationTitle, "Test Notification"),
        Copy("Test Notification's help tag", SettingsOptions.testNotificationHelp, "Shows a test notification with a sample event."),
        // "Snooze", not "snooze button": the notification offers them in a menu (2026-10-19).
        Copy("First snooze row", SettingsOptions.firstSnoozeTitle, "First snooze"),
        Copy("Second snooze row", SettingsOptions.secondSnoozeTitle, "Second snooze"),
        Copy("First snooze's custom field", SettingsOptions.firstSnoozeFieldLabel, "First snooze, minutes"),
        Copy("Second snooze's custom field", SettingsOptions.secondSnoozeFieldLabel, "Second snooze, minutes"),
        // Clearer about both kinds using these, as the user asked (2026-10-19).
        Copy(
            "Snooze footnote",
            SettingsOptions.snoozeFootnote,
            "The full-screen alert's snooze buttons and the notification's menu both offer these two times, then At event start."
        ),
        Copy("Calendars' warning with none checked", SettingsOptions.noCalendarsWarning, "No calendars selected: you won't get any alerts."),
        // An account's count stands alone under its box since 2026-10-19, so it says "selected" like the pane's total.
        Copy("Calendars' count", SettingsOptions.calendarsSelected(2, of: 2), "2 of 2 selected"),
        Copy("Calendars' count with none checked", SettingsOptions.calendarsSelected(0, of: 5), "0 of 5 selected"),
        // Show Demo until the user found the demo buttons' labels confusing (2026-10-19).
        Copy("Test Full-Screen Alert", SettingsOptions.testFullScreenAlertTitle, "Test Full-Screen Alert"),
        Copy(
            "Test Full-Screen Alert's help tag",
            SettingsOptions.testFullScreenAlertHelp,
            "Shows a test full-screen alert with a sample event. Press Esc to close it."
        ),
        Copy("Test Full-Screen Alert's help tag during an alert", SettingsOptions.testFullScreenAlertUnavailableHelp, "Close the current full-screen alert first."),
        Copy("Colors section", SettingsOptions.colorsSectionTitle, "Colors"),
        Copy("Appearance's Never note", SettingsOptions.alertMeNeverNote, "Alert me is set to Never in Alerts. Test Full-Screen Alert still works."),
        Copy("Restore Defaults' help tag", SettingsOptions.restoreAppearanceHelp, "Goes back to the Dark style. Your own style stays on the Custom card."),
        Copy("Events section", SettingsOptions.eventsSectionTitle, "Events"),
        Copy("Events with no participants row", SettingsOptions.eventsWithoutParticipantsTitle, "Events with no participants"),
        Copy("Out-of-office events row", SettingsOptions.outOfOfficeEventsTitle, "Out-of-office events"),
        Copy("Out-of-office keywords row", SettingsOptions.outOfOfficeKeywordsTitle, "Out-of-office keywords"),
        Copy(
            "Events footnote",
            SettingsOptions.eventsFootnote,
            "An event counts as out of office when its title contains any of these words. Press Return to add one. Only Show and alert lets an event alert, take the menu bar or sit at the top of the panel. When an event is both kinds, the choice that shows less wins."
        ),
        // A fixture run is marked on every pane, so it can't pass for the real app.
        Copy("window title", SettingsOptions.windowTitle(pane: "General", isFixture: false), "General"),
        Copy("window title in a fixture run", SettingsOptions.windowTitle(pane: "General", isFixture: true), "General (fixture)"),
    ]

    @Test(arguments: copy)
    func settingsCopy(_ copy: Copy) {
        #expect(copy.actual == copy.expected)
    }

    /// The footnotes name what they point at as it's named elsewhere, so a rename can't leave them stale: the
    /// Snooze box's the button both kinds add after the durations, the Notification box's the bell menu's
    /// Pause alerts, Appearance's Never note the pane Alert me is on and the button that still works.
    @Test func theAlertsFootnotesNameWhatTheyPointAt() {
        #expect(SettingsOptions.snoozeFootnote.contains(AlertCountdown.snoozeUntilStartLabel))
        #expect(SettingsOptions.notificationFootnote.contains(PauseCopy.pauseTitle.lowercased()))
        #expect(SettingsOptions.alertMeNeverNote.contains(" in \(SettingsOptions.alertsPaneTitle)."))
        #expect(SettingsOptions.alertMeNeverNote.contains(SettingsOptions.testFullScreenAlertTitle + " still works."))
    }

    /// The footnote names the choice as the pop-up does, so renaming the choice can't leave it stale.
    @Test func theEventsFootnoteNamesShowAndAlert() {
        #expect(SettingsOptions.eventsFootnote.contains(EventVisibility.showAndAlert.title))
    }

    // MARK: Calendars

    /// Rounded down, and a time in the future (the clock moved back) reads as just now. The Calendars pane
    /// shows it after "Updated".
    @Test(arguments: [
        (-3600, "just now"),
        (0, "just now"),
        (59.9, "just now"),
        (60, "1 minute ago"),
        (119, "1 minute ago"),
        (2 * 60, "2 minutes ago"),
        (3600 - 1, "59 minutes ago"),
        (2 * 3600 - 1, "1 hour ago"),
        (23 * 3600 + 59 * 60, "23 hours ago"),
        (24 * 3600, "1 day ago"),
        (48 * 3600 - 1, "1 day ago"),
        (30 * 24 * 3600, "30 days ago"),
    ] as [(TimeInterval, String)])
    func relativeTimeRoundsDown(seconds: TimeInterval, expected: String) {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let now = start.addingTimeInterval(seconds)
        #expect(SettingsOptions.relativeTime(since: start, now: now) == expected)
        #expect(SettingsOptions.updatedLabel(lastRefreshed: start, now: now) == "Updated " + expected)
    }

    @Test func calendarSelectionCountsAndGroupToggles() {
        let all = ["work", "home", "birthdays", "holidays"]
        #expect(CalendarSelection.enabledCount(of: all, in: nil) == 4)
        #expect(CalendarSelection.enabledCount(of: all, in: ["work", "gone"]) == 1)

        let deselected = CalendarSelection.setting(["birthdays", "holidays"], enabled: false, in: nil, allCalendarIDs: all)
        #expect(deselected == ["work", "home"])
        let reselected = CalendarSelection.setting(["birthdays", "holidays"], enabled: true, in: deselected, allCalendarIDs: all)
        #expect(reselected == Set(all))
        #expect(CalendarSelection.setting(["work"], enabled: true, in: [], allCalendarIDs: all) == ["work"])
    }

    // MARK: Out-of-office keywords

    @Test func addingKeywordsTrimsAndSkipsDuplicates() {
        let keywords = ["out of office", "OOO"]
        #expect(KeywordList.adding("  vacation ", to: keywords) == ["out of office", "OOO", "vacation"])
        #expect(KeywordList.adding("ooo", to: keywords) == keywords)
        #expect(KeywordList.adding("   ", to: keywords) == keywords)
    }

    @Test func commaEndsAKeyword() {
        let start = ["OOO"]
        let typing = KeywordList.splittingDraft("vaca", into: start)
        #expect(typing.keywords == start)
        #expect(typing.draft == "vaca")

        let comma = KeywordList.splittingDraft("vacation,", into: start)
        #expect(comma.keywords == ["OOO", "vacation"])
        #expect(comma.draft == "")

        let pasted = KeywordList.splittingDraft("holiday, ooo, sick, lea", into: start)
        #expect(pasted.keywords == ["OOO", "holiday", "sick"])
        #expect(pasted.draft == "lea")
    }
}
