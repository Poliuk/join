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
        MinutesPopUp(
            testDescription: "Snooze",
            presets: SettingsOptions.snoozeMinutes, expectedPresets: [1, 3, 5, 10],
            range: SettingsOptions.customSnoozeRange, expectedRange: 1...120,
            defaults: Preferences.defaultSnoozeDurations.map(SettingsOptions.wholeMinutes)
        ),
        MinutesPopUp(
            testDescription: "Starting soon",
            presets: SettingsOptions.startingSoonMinutes, expectedPresets: [1, 3, 5, 10],
            range: StartingSoonPill.minuteRange, expectedRange: StartingSoonPill.minuteRange,
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
        Copy("auto-close row", SettingsOptions.autoCloseRowTitle, "Close automatically"),
        Copy("Show Demo's help tag", SettingsOptions.showDemoHelp, "Shows a real full-screen alert with a sample event. Press Esc to close it."),
        Copy("Show Demo's help tag during an alert", SettingsOptions.showDemoUnavailableHelp, "Close the current full-screen alert first."),
        Copy("Colors section", SettingsOptions.colorsSectionTitle, "Colors"),
        Copy("Appearance's Never note", SettingsOptions.alertMeNeverNote, "Alert me is set to Never in Full-Screen Alert. Show Demo still works."),
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
