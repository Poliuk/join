import XCTest
@testable import JoinCore

final class SettingsOptionsTests: XCTestCase {
    func testLeadTimePresetsAreWholeMinutesWithoutSeconds() {
        XCTAssertEqual(SettingsOptions.leadTimeMinutes, [0, 1, 2, 3, 5, 10])
        XCTAssertEqual(SettingsOptions.leadTimeTitle(minutes: 0), "When the event starts")
        XCTAssertEqual(SettingsOptions.leadTimeTitle(minutes: 1), "1 minute before")
        XCTAssertEqual(SettingsOptions.leadTimeTitle(minutes: 5), "5 minutes before")
        XCTAssertEqual(SettingsOptions.customLeadTimeRange, 0...120)
    }

    func testLeadTimeOutsideTheListIsCustom() {
        XCTAssertTrue(SettingsOptions.isPresetLeadTime(0))
        XCTAssertTrue(SettingsOptions.isPresetLeadTime(180))
        XCTAssertTrue(SettingsOptions.isPresetLeadTime(600))
        XCTAssertFalse(SettingsOptions.isPresetLeadTime(7 * 60))
        XCTAssertFalse(SettingsOptions.isPresetLeadTime(120 * 60))
    }

    func testSnoozeChoicesKeepAStoredValueThatIsNotInTheList() {
        XCTAssertEqual(SettingsOptions.snoozeChoices(including: 5), [1, 2, 3, 5, 10, 15, 30, 60])
        XCTAssertEqual(SettingsOptions.snoozeChoices(including: 7), [1, 2, 3, 5, 7, 10, 15, 30, 60])
        XCTAssertEqual(SettingsOptions.snoozeChoices(including: 45), [1, 2, 3, 5, 10, 15, 30, 45, 60])
    }

    func testDurationTitles() {
        XCTAssertEqual(SettingsOptions.durationTitle(minutes: 1), "1 minute")
        XCTAssertEqual(SettingsOptions.durationTitle(minutes: 30), "30 minutes")
        XCTAssertEqual(SettingsOptions.durationTitle(minutes: 60), "1 hour")
        XCTAssertEqual(SettingsOptions.durationTitle(minutes: 120), "2 hours")
        XCTAssertEqual(SettingsOptions.durationTitle(minutes: 90), "90 minutes")
        XCTAssertEqual(SettingsOptions.shortDurationTitle(minutes: 5), "5 min")
        XCTAssertEqual(SettingsOptions.shortDurationTitle(minutes: 60), "1 hr")
    }

    func testAlertOffersBothSnoozesThenEventStart() {
        XCTAssertEqual(SettingsOptions.alertOffers(snoozeDurations: [60, 300]), ["1 min", "5 min", "At event start"])
        XCTAssertEqual(SettingsOptions.alertOffers(snoozeDurations: [600, 3600]), ["10 min", "1 hr", "At event start"])
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
}
