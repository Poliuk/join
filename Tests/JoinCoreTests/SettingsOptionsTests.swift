import Foundation
import Testing
@testable import JoinCore

struct SettingsOptionsTests {
    @Test func leadTimePresetsAreWholeMinutesWithoutSeconds() {
        #expect(SettingsOptions.leadTimeMinutes == [0, 1, 3, 5])
        #expect(SettingsOptions.leadTimeMinutes.map(SettingsOptions.leadTimeTitle(minutes:)) == [
            "When the event starts", "1 minute before", "3 minutes before", "5 minutes before",
        ])
        #expect(SettingsOptions.customLeadTimeRange == 0...120)
    }

    @Test @MainActor func theDefaultLeadTimeIsAPresetAndEarlierPresetsShowAsCustom() {
        #expect(SettingsOptions.leadTimeMinutes.contains(SettingsOptions.wholeMinutes(Preferences.defaultLeadTime)))
        for minutes in [2, 10] {
            #expect(!SettingsOptions.leadTimeMinutes.contains(minutes), "\(minutes) shows as Custom…")
            #expect(SettingsOptions.customLeadTimeRange.contains(minutes), "\(minutes) fits the custom field")
        }
    }

    @Test func alertMeNeverTitle() {
        #expect(SettingsOptions.leadTimeNeverTitle == "Never")
    }

    @Test func paneCopy() {
        #expect(SettingsOptions.menuBarSectionTitle == "Menu bar")
        #expect(SettingsOptions.menuBarShowsTitle == "Shows")
        #expect(SettingsOptions.autoCloseRowTitle == "Close automatically")
        #expect(SettingsOptions.showDemoHelp == "Shows a real full-screen alert with a sample event. Press Esc to close it.")
        #expect(SettingsOptions.showDemoUnavailableHelp == "Close the current full-screen alert first.")
        #expect(SettingsOptions.colorsSectionTitle == "Colors")
        #expect(SettingsOptions.alertMeNeverNote == "Alert me is set to Never in Full-Screen Alert. Show Demo still works.")
        #expect(SettingsOptions.restoreAppearanceHelp == "Goes back to the Dark style. Your own style stays on the Custom card.")
    }

    @Test func menuBarPillCopy() {
        #expect(SettingsOptions.startingSoonRowTitle == "Starting soon")
        #expect(SettingsOptions.startingSoonHelp == "The menu bar shows the event like this from then on. The panel highlights it at the same time.")
        #expect(SettingsOptions.startingSoonFieldLabel == "Minutes before the event")
        #expect(SettingsOptions.menuBarPreviewLabel == "Preview of the menu bar before an event")
        #expect(SettingsOptions.menuBarColorTitle == "Color")
        #expect(SettingsOptions.menuBarColorAccessibilityTitle == "Menu bar fill")
        #expect(SettingsOptions.menuBarColorWellLabel == "Menu bar fill color")
        #expect(SettingsOptions.menuBarTextAccessibilityTitle == "Menu bar text")
        #expect(SettingsOptions.menuBarTextWellLabel == "Menu bar text color")
    }

    @Test @MainActor func snoozePresetsAndCustomRange() {
        #expect(SettingsOptions.snoozeMinutes == [1, 3, 5, 10])
        #expect(SettingsOptions.customSnoozeRange == 1...120)
        let defaults = Preferences.defaultSnoozeDurations.map(SettingsOptions.wholeMinutes)
        #expect(defaults.allSatisfy(SettingsOptions.snoozeMinutes.contains), "the default snoozes are presets")
    }

    @Test func customMinuteUnits() {
        #expect(SettingsOptions.minutesBeforeUnit(1) == "minute before")
        #expect(SettingsOptions.minutesBeforeUnit(7) == "minutes before")
        #expect(SettingsOptions.minutesUnit(1) == "minute")
        #expect(SettingsOptions.minutesUnit(45) == "minutes")
    }

    @Test func durationTitles() {
        let cases: [(minutes: Int, long: String, short: String)] = [
            (1, "1 minute", "1 min"), (5, "5 minutes", "5 min"), (30, "30 minutes", "30 min"),
            (60, "1 hour", "1 hr"), (90, "90 minutes", "90 min"), (120, "2 hours", "2 hr"),
        ]
        for c in cases {
            #expect(SettingsOptions.durationTitle(minutes: c.minutes) == c.long, "\(c.minutes) min")
            #expect(SettingsOptions.shortDurationTitle(minutes: c.minutes) == c.short, "\(c.minutes) min")
        }
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

    @Test func openAtLoginReadsOnWhileWaitingForApproval() {
        #expect(!SettingsOptions.opensAtLogin(.notRegistered))
        #expect(!SettingsOptions.opensAtLogin(.notFound))
        #expect(SettingsOptions.opensAtLogin(.requiresApproval))
        #expect(SettingsOptions.opensAtLogin(.enabled))
    }

    @Test func openAtLoginHintClearsOnceApproved() {
        #expect(SettingsOptions.openAtLoginHint(.requiresApproval)
                == "Allow Join! in System Settings › General › Login Items to open it at login.")
        #expect(SettingsOptions.openAtLoginHint(.enabled) == nil)
        #expect(SettingsOptions.openAtLoginHint(.notRegistered) == nil)
        #expect(SettingsOptions.openAtLoginHint(.notFound) == nil)
    }

    @Test func windowTitleMarksFixtureRuns() {
        #expect(SettingsOptions.windowTitle(pane: "General", isFixture: false) == "General")
        #expect(SettingsOptions.windowTitle(pane: "General", isFixture: true) == "General (fixture)")
        #expect(SettingsOptions.windowTitle(pane: "Appearance", isFixture: true) == "Appearance (fixture)")
    }

    @Test func updatedLabel() {
        let refreshed = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func label(after seconds: TimeInterval) -> String {
            SettingsOptions.updatedLabel(lastRefreshed: refreshed, now: refreshed.addingTimeInterval(seconds))
        }
        #expect(label(after: -5) == "Updated just now")
        #expect(label(after: 59) == "Updated just now")
        #expect(label(after: 60) == "Updated 1 minute ago")
        #expect(label(after: 14 * 60 + 30) == "Updated 14 minutes ago")
        #expect(label(after: 3600) == "Updated 1 hour ago")
        #expect(label(after: 5 * 3600) == "Updated 5 hours ago")
        #expect(label(after: 50 * 3600) == "Updated 2 days ago")
        #expect(label(after: 24 * 3600) == "Updated 1 day ago")
        #expect(label(after: 119) == "Updated 1 minute ago")
    }

    @Test func relativeTimeRoundsDown() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func relative(after seconds: TimeInterval) -> String {
            SettingsOptions.relativeTime(since: start, now: start.addingTimeInterval(seconds))
        }
        #expect(relative(after: -3600) == "just now")
        #expect(relative(after: 0) == "just now")
        #expect(relative(after: 59.9) == "just now")
        #expect(relative(after: 60) == "1 minute ago")
        #expect(relative(after: 2 * 60) == "2 minutes ago")
        #expect(relative(after: 3600 - 1) == "59 minutes ago")
        #expect(relative(after: 2 * 3600 - 1) == "1 hour ago")
        #expect(relative(after: 23 * 3600 + 59 * 60) == "23 hours ago")
        #expect(relative(after: 48 * 3600 - 1) == "1 day ago")
        #expect(relative(after: 30 * 24 * 3600) == "30 days ago")
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

    @Test func eventsSectionCopy() {
        #expect(SettingsOptions.eventsSectionTitle == "Events")
        #expect(SettingsOptions.eventsWithoutParticipantsTitle == "Events with no participants")
        #expect(SettingsOptions.outOfOfficeEventsTitle == "Out-of-office events")
        #expect(SettingsOptions.outOfOfficeKeywordsTitle == "Out-of-office keywords")
        #expect(
            SettingsOptions.eventsFootnote
                == "An event counts as out of office when its title contains any of these words. Press Return to add one. Only Show and alert lets an event alert, take the menu bar or sit at the top of the panel. When an event is both kinds, the choice that shows less wins."
        )
        #expect(SettingsOptions.eventsFootnote.contains(EventVisibility.showAndAlert.title), "names the choice as the pop-up does")
    }

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

    @Test func startingSoonPresets() {
        #expect(SettingsOptions.startingSoonMinutes == [1, 3, 5, 10])
        #expect(SettingsOptions.startingSoonMinutes.contains(StartingSoonPill.default.minutes), "the default is a preset")
        #expect(SettingsOptions.startingSoonMinutes.allSatisfy(StartingSoonPill.minuteRange.contains))
        #expect(SettingsOptions.startingSoonTitle(minutes: 1) == "1 minute before")
        #expect(SettingsOptions.startingSoonTitle(minutes: 5) == "5 minutes before")
    }
}
