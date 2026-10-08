import XCTest
@testable import JoinCore

final class SettingsOptionsTests: XCTestCase {
    func testLeadTimePresetsAreWholeMinutesWithoutSeconds() {
        XCTAssertEqual(SettingsOptions.leadTimeMinutes, [0, 1, 3, 5])
        XCTAssertEqual(SettingsOptions.leadTimeMinutes.map(SettingsOptions.leadTimeTitle(minutes:)), [
            "When the event starts", "1 minute before", "3 minutes before", "5 minutes before",
        ])
        XCTAssertEqual(SettingsOptions.customLeadTimeRange, 0...120)
    }

    @MainActor
    func testTheDefaultLeadTimeIsAPresetAndEarlierPresetsShowAsCustom() {
        XCTAssertTrue(SettingsOptions.leadTimeMinutes.contains(SettingsOptions.wholeMinutes(Preferences.defaultLeadTime)))
        for minutes in [2, 10] {
            XCTAssertFalse(SettingsOptions.leadTimeMinutes.contains(minutes), "\(minutes) shows as Custom…")
            XCTAssertTrue(SettingsOptions.customLeadTimeRange.contains(minutes), "\(minutes) fits the custom field")
        }
    }

    func testAlertMeNeverTitle() {
        XCTAssertEqual(SettingsOptions.leadTimeNeverTitle, "Never")
    }

    func testPaneCopy() {
        XCTAssertEqual(SettingsOptions.menuBarSectionTitle, "Menu bar")
        XCTAssertEqual(SettingsOptions.menuBarShowsTitle, "Shows")
        XCTAssertEqual(SettingsOptions.autoCloseRowTitle, "Close automatically")
        XCTAssertEqual(SettingsOptions.showDemoHelp, "Shows a real full-screen alert with a sample event. Press Esc to close it.")
        XCTAssertEqual(SettingsOptions.showDemoUnavailableHelp, "Close the current full-screen alert first.")
        XCTAssertEqual(SettingsOptions.colorsSectionTitle, "Colors")
        XCTAssertEqual(SettingsOptions.alertMeNeverNote, "Alert me is set to Never in Full-Screen Alert. Show Demo still works.")
        XCTAssertEqual(SettingsOptions.restoreAppearanceHelp, "Goes back to the Dark style. Your own style stays on the Custom card.")
    }

    func testMenuBarPillCopy() {
        XCTAssertEqual(SettingsOptions.startingSoonRowTitle, "Starting soon")
        XCTAssertEqual(SettingsOptions.startingSoonHelp, "The menu bar shows the event like this from then on. The panel highlights it at the same time.")
        XCTAssertEqual(SettingsOptions.startingSoonFieldLabel, "Minutes before the event")
        XCTAssertEqual(SettingsOptions.menuBarPreviewLabel, "Preview of the menu bar before an event")
        XCTAssertEqual(SettingsOptions.menuBarColorTitle, "Color")
        XCTAssertEqual(SettingsOptions.menuBarColorAccessibilityTitle, "Menu bar fill")
        XCTAssertEqual(SettingsOptions.menuBarColorWellLabel, "Menu bar fill color")
        XCTAssertEqual(SettingsOptions.menuBarTextAccessibilityTitle, "Menu bar text")
        XCTAssertEqual(SettingsOptions.menuBarTextWellLabel, "Menu bar text color")
    }

    @MainActor
    func testSnoozePresetsAndCustomRange() {
        XCTAssertEqual(SettingsOptions.snoozeMinutes, [1, 3, 5, 10])
        XCTAssertEqual(SettingsOptions.customSnoozeRange, 1...120)
        let defaults = Preferences.defaultSnoozeDurations.map(SettingsOptions.wholeMinutes)
        XCTAssertTrue(defaults.allSatisfy(SettingsOptions.snoozeMinutes.contains), "the default snoozes are presets")
    }

    func testCustomMinuteUnits() {
        XCTAssertEqual(SettingsOptions.minutesBeforeUnit(1), "minute before")
        XCTAssertEqual(SettingsOptions.minutesBeforeUnit(7), "minutes before")
        XCTAssertEqual(SettingsOptions.minutesUnit(1), "minute")
        XCTAssertEqual(SettingsOptions.minutesUnit(45), "minutes")
    }

    func testDurationTitles() {
        let cases: [(minutes: Int, long: String, short: String)] = [
            (1, "1 minute", "1 min"), (5, "5 minutes", "5 min"), (30, "30 minutes", "30 min"),
            (60, "1 hour", "1 hr"), (90, "90 minutes", "90 min"), (120, "2 hours", "2 hr"),
        ]
        for c in cases {
            XCTAssertEqual(SettingsOptions.durationTitle(minutes: c.minutes), c.long, "\(c.minutes) min")
            XCTAssertEqual(SettingsOptions.shortDurationTitle(minutes: c.minutes), c.short, "\(c.minutes) min")
        }
    }

    func testAutoCloseMapsNeverAndMinutes() {
        XCTAssertNil(SettingsOptions.autoCloseSelection(enabled: false, after: 900))
        XCTAssertEqual(SettingsOptions.autoCloseSelection(enabled: true, after: 900), 15)
        XCTAssertEqual(SettingsOptions.autoCloseChoices(including: nil), [5, 10, 15, 30, 60])
        XCTAssertEqual(SettingsOptions.autoCloseChoices(including: 15), [5, 10, 15, 30, 60])
        XCTAssertEqual(SettingsOptions.autoCloseChoices(including: 20), [5, 10, 15, 20, 30, 60])
        XCTAssertEqual(SettingsOptions.autoCloseTitle(minutes: nil), "Never")
        XCTAssertEqual(SettingsOptions.autoCloseTitle(minutes: 5), "After 5 minutes")
        XCTAssertEqual(SettingsOptions.autoCloseTitle(minutes: 60), "After 1 hour")
    }

    func testOpenAtLoginReadsOnWhileWaitingForApproval() {
        XCTAssertFalse(SettingsOptions.opensAtLogin(.notRegistered))
        XCTAssertFalse(SettingsOptions.opensAtLogin(.notFound))
        XCTAssertTrue(SettingsOptions.opensAtLogin(.requiresApproval))
        XCTAssertTrue(SettingsOptions.opensAtLogin(.enabled))
    }

    func testOpenAtLoginHintClearsOnceApproved() {
        XCTAssertEqual(SettingsOptions.openAtLoginHint(.requiresApproval),
                       "Allow Join! in System Settings › General › Login Items to open it at login.")
        XCTAssertNil(SettingsOptions.openAtLoginHint(.enabled))
        XCTAssertNil(SettingsOptions.openAtLoginHint(.notRegistered))
        XCTAssertNil(SettingsOptions.openAtLoginHint(.notFound))
    }

    func testWindowTitleMarksFixtureRuns() {
        XCTAssertEqual(SettingsOptions.windowTitle(pane: "General", isFixture: false), "General")
        XCTAssertEqual(SettingsOptions.windowTitle(pane: "General", isFixture: true), "General (fixture)")
        XCTAssertEqual(SettingsOptions.windowTitle(pane: "Appearance", isFixture: true), "Appearance (fixture)")
    }

    func testUpdatedLabel() {
        let refreshed = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func label(after seconds: TimeInterval) -> String {
            SettingsOptions.updatedLabel(lastRefreshed: refreshed, now: refreshed.addingTimeInterval(seconds))
        }
        XCTAssertEqual(label(after: -5), "Updated just now")
        XCTAssertEqual(label(after: 59), "Updated just now")
        XCTAssertEqual(label(after: 60), "Updated 1 minute ago")
        XCTAssertEqual(label(after: 14 * 60 + 30), "Updated 14 minutes ago")
        XCTAssertEqual(label(after: 3600), "Updated 1 hour ago")
        XCTAssertEqual(label(after: 5 * 3600), "Updated 5 hours ago")
        XCTAssertEqual(label(after: 50 * 3600), "Updated 2 days ago")
        XCTAssertEqual(label(after: 24 * 3600), "Updated 1 day ago")
        XCTAssertEqual(label(after: 119), "Updated 1 minute ago")
    }

    func testRelativeTimeRoundsDown() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func relative(after seconds: TimeInterval) -> String {
            SettingsOptions.relativeTime(since: start, now: start.addingTimeInterval(seconds))
        }
        XCTAssertEqual(relative(after: -3600), "just now")
        XCTAssertEqual(relative(after: 0), "just now")
        XCTAssertEqual(relative(after: 59.9), "just now")
        XCTAssertEqual(relative(after: 60), "1 minute ago")
        XCTAssertEqual(relative(after: 2 * 60), "2 minutes ago")
        XCTAssertEqual(relative(after: 3600 - 1), "59 minutes ago")
        XCTAssertEqual(relative(after: 2 * 3600 - 1), "1 hour ago")
        XCTAssertEqual(relative(after: 23 * 3600 + 59 * 60), "23 hours ago")
        XCTAssertEqual(relative(after: 48 * 3600 - 1), "1 day ago")
        XCTAssertEqual(relative(after: 30 * 24 * 3600), "30 days ago")
    }

    func testCalendarSelectionCountsAndGroupToggles() {
        let all = ["work", "home", "birthdays", "holidays"]
        XCTAssertEqual(CalendarSelection.enabledCount(of: all, in: nil), 4)
        XCTAssertEqual(CalendarSelection.enabledCount(of: all, in: ["work", "gone"]), 1)

        let deselected = CalendarSelection.setting(["birthdays", "holidays"], enabled: false, in: nil, allCalendarIDs: all)
        XCTAssertEqual(deselected, ["work", "home"])
        let reselected = CalendarSelection.setting(["birthdays", "holidays"], enabled: true, in: deselected, allCalendarIDs: all)
        XCTAssertEqual(reselected, Set(all))
        XCTAssertEqual(CalendarSelection.setting(["work"], enabled: true, in: [], allCalendarIDs: all), ["work"])
    }

    func testEventsSectionCopy() {
        XCTAssertEqual(SettingsOptions.eventsSectionTitle, "Events")
        XCTAssertEqual(SettingsOptions.eventsWithoutParticipantsTitle, "Events with no participants")
        XCTAssertEqual(SettingsOptions.outOfOfficeEventsTitle, "Out-of-office events")
        XCTAssertEqual(SettingsOptions.outOfOfficeKeywordsTitle, "Out-of-office keywords")
        XCTAssertEqual(
            SettingsOptions.eventsFootnote,
            "An event counts as out of office when its title contains any of these words. Press Return to add one. Only Show and alert lets an event alert, take the menu bar or sit at the top of the panel. When an event is both kinds, the choice that shows less wins."
        )
        XCTAssertTrue(SettingsOptions.eventsFootnote.contains(EventVisibility.showAndAlert.title), "names the choice as the pop-up does")
    }

    func testAddingKeywordsTrimsAndSkipsDuplicates() {
        let keywords = ["out of office", "OOO"]
        XCTAssertEqual(KeywordList.adding("  vacation ", to: keywords), ["out of office", "OOO", "vacation"])
        XCTAssertEqual(KeywordList.adding("ooo", to: keywords), keywords)
        XCTAssertEqual(KeywordList.adding("   ", to: keywords), keywords)
    }

    func testCommaEndsAKeyword() {
        let start = ["OOO"]
        let typing = KeywordList.splittingDraft("vaca", into: start)
        XCTAssertEqual(typing.keywords, start)
        XCTAssertEqual(typing.draft, "vaca")

        let comma = KeywordList.splittingDraft("vacation,", into: start)
        XCTAssertEqual(comma.keywords, ["OOO", "vacation"])
        XCTAssertEqual(comma.draft, "")

        let pasted = KeywordList.splittingDraft("holiday, ooo, sick, lea", into: start)
        XCTAssertEqual(pasted.keywords, ["OOO", "holiday", "sick"])
        XCTAssertEqual(pasted.draft, "lea")
    }

    func testStartingSoonPresets() {
        XCTAssertEqual(SettingsOptions.startingSoonMinutes, [1, 3, 5, 10])
        XCTAssertTrue(SettingsOptions.startingSoonMinutes.contains(StartingSoonPill.default.minutes), "the default is a preset")
        XCTAssertTrue(SettingsOptions.startingSoonMinutes.allSatisfy(StartingSoonPill.minuteRange.contains))
        XCTAssertEqual(SettingsOptions.startingSoonTitle(minutes: 1), "1 minute before")
        XCTAssertEqual(SettingsOptions.startingSoonTitle(minutes: 5), "5 minutes before")
    }
}
