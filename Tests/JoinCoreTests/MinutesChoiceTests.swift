import XCTest
@testable import JoinCore

final class MinutesChoiceTests: XCTestCase {
    private let alertMe = MinutesChoice(presets: SettingsOptions.leadTimeMinutes, offersNever: true)
    private let snooze = MinutesChoice(presets: SettingsOptions.snoozeMinutes)
    private let appears = MinutesChoice(presets: SettingsOptions.startingSoonMinutes)

    // MARK: Alert me

    func testAlertMeShowsAPresetWhileAlertsAreOn() {
        for minutes in SettingsOptions.leadTimeMinutes {
            XCTAssertEqual(alertMe.selection(minutes: minutes, neverChosen: false, customPicked: false), .preset(minutes))
            XCTAssertFalse(alertMe.opensAsCustom(minutes: minutes, neverChosen: false), "\(minutes) min is a preset")
            XCTAssertFalse(alertMe.showsCustomRow(minutes: minutes, neverChosen: false, customPicked: false))
        }
    }

    func testAlertMeShowsNeverWhileAlertsAreOffWhateverTheTime() {
        for minutes in [0, 1, 2, 3, 5, 10, 120] {
            XCTAssertEqual(alertMe.selection(minutes: minutes, neverChosen: true, customPicked: false), .never, "\(minutes) min")
            XCTAssertFalse(alertMe.opensAsCustom(minutes: minutes, neverChosen: true), "\(minutes) min")
            XCTAssertFalse(alertMe.showsCustomRow(minutes: minutes, neverChosen: true, customPicked: false), "\(minutes) min")
        }
    }

    func testAStored2Or10ShowsAsCustomOnlyWhileAlertsAreOn() {
        for minutes in [2, 10] {
            XCTAssertTrue(alertMe.opensAsCustom(minutes: minutes, neverChosen: false), "\(minutes) min")
            XCTAssertEqual(alertMe.selection(minutes: minutes, neverChosen: false, customPicked: false), .custom, "\(minutes) min")
            XCTAssertTrue(alertMe.showsCustomRow(minutes: minutes, neverChosen: false, customPicked: false), "\(minutes) min")
            XCTAssertEqual(alertMe.selection(minutes: minutes, neverChosen: true, customPicked: false), .never, "\(minutes) min")
        }
    }

    func testNeverIsKeptApartFromWhenTheEventStartsAndCustom() {
        XCTAssertNotEqual(MinutesChoice.Item.never, .preset(0))
        XCTAssertNotEqual(MinutesChoice.Item.never, .custom)
        XCTAssertNotEqual(MinutesChoice.Item.custom, .preset(0))
        XCTAssertEqual(alertMe.selection(minutes: 0, neverChosen: false, customPicked: false), .preset(0), "When the event starts isn't Never")
        XCTAssertEqual(alertMe.selection(minutes: 0, neverChosen: true, customPicked: false), .never)
        let items: Set<MinutesChoice.Item> = Set(SettingsOptions.leadTimeMinutes.map(MinutesChoice.Item.preset) + [.never, .custom])
        XCTAssertEqual(items.count, SettingsOptions.leadTimeMinutes.count + 2, "every item has a tag of its own")
    }

    func testCustomPickedKeepsShowingWhenItsValueMatchesAPresetOrNeverStillHolds() {
        XCTAssertEqual(alertMe.selection(minutes: 3, neverChosen: false, customPicked: true), .custom)
        XCTAssertTrue(alertMe.showsCustomRow(minutes: 3, neverChosen: false, customPicked: true))
        XCTAssertEqual(alertMe.selection(minutes: 3, neverChosen: true, customPicked: true), .custom, "Custom… picked from Never")
        XCTAssertTrue(alertMe.showsCustomRow(minutes: 3, neverChosen: true, customPicked: true))
    }

    func testPickingAPresetSavesItAndTurnsNeverOff() {
        XCTAssertEqual(alertMe.picking(.preset(5)), MinutesChoice.Pick(customPicked: false, minutes: 5, neverChosen: false))
        XCTAssertEqual(alertMe.picking(.preset(0)), MinutesChoice.Pick(customPicked: false, minutes: 0, neverChosen: false))
    }

    func testPickingNeverKeepsTheTime() {
        XCTAssertEqual(alertMe.picking(.never), MinutesChoice.Pick(customPicked: false, minutes: nil, neverChosen: true))
    }

    func testPickingCustomKeepsTheTimeAndTurnsNeverOffAtOnce() {
        XCTAssertEqual(alertMe.picking(.custom), MinutesChoice.Pick(customPicked: true, minutes: nil, neverChosen: false))
        XCTAssertEqual(snooze.picking(.custom), MinutesChoice.Pick(customPicked: true, minutes: nil, neverChosen: nil),
                       "a pop-up without Never leaves it alone")
    }

    func testCustomPickedAfterAChange() {
        // Saved by the pop-up: Custom… stays picked, and a value that isn't a preset picks it.
        XCTAssertTrue(alertMe.customPicked(afterChangeTo: 5, neverChosen: false, customPicked: true, savedHere: true),
                      "a custom value that matches a preset stays Custom…")
        XCTAssertTrue(alertMe.customPicked(afterChangeTo: 7, neverChosen: false, customPicked: false, savedHere: true))
        XCTAssertFalse(alertMe.customPicked(afterChangeTo: 5, neverChosen: false, customPicked: false, savedHere: true), "a preset picked")
        // From elsewhere (Restore Defaults): as on opening the pane.
        XCTAssertFalse(alertMe.customPicked(afterChangeTo: 3, neverChosen: false, customPicked: true, savedHere: false))
        XCTAssertTrue(alertMe.customPicked(afterChangeTo: 7, neverChosen: false, customPicked: false, savedHere: false))
        XCTAssertFalse(alertMe.customPicked(afterChangeTo: 7, neverChosen: true, customPicked: true, savedHere: false))
    }

    /// The pop-up's own steps, as `SettingsMinutesChoice` takes them.
    private struct PopUp {
        let rule: MinutesChoice
        var minutes: Int
        var neverChosen: Bool
        var customPicked: Bool

        init(rule: MinutesChoice, minutes: Int, neverChosen: Bool = false) {
            self.rule = rule
            self.minutes = minutes
            self.neverChosen = neverChosen
            customPicked = rule.opensAsCustom(minutes: minutes, neverChosen: neverChosen)
        }

        var selection: MinutesChoice.Item {
            rule.selection(minutes: minutes, neverChosen: neverChosen, customPicked: customPicked)
        }

        mutating func pick(_ item: MinutesChoice.Item) {
            let pick = rule.picking(item)
            customPicked = pick.customPicked
            if let value = pick.minutes { save(value) }
            if let never = pick.neverChosen { neverChosen = never }
        }

        mutating func saveCustom(_ value: Int) {
            save(value)
        }

        private mutating func save(_ value: Int) {
            guard value != minutes else { return }
            minutes = value
            customPicked = rule.customPicked(afterChangeTo: value, neverChosen: neverChosen, customPicked: customPicked, savedHere: true)
        }
    }

    func testCustomFromNeverTurnsAlertsBackOnAtOnceWithTheKeptTime() {
        var popUp = PopUp(rule: alertMe, minutes: 3, neverChosen: true)
        XCTAssertEqual(popUp.selection, .never)
        popUp.pick(.custom)
        XCTAssertEqual(popUp.selection, .custom)
        XCTAssertFalse(popUp.neverChosen, "what the pop-up shows is what's in effect")
        XCTAssertEqual(popUp.minutes, 3, "the field starts at the kept time")
        popUp.pick(.never)
        popUp.saveCustom(popUp.minutes)   // the row's save as it disappears
        XCTAssertEqual(popUp.selection, .never)
        XCTAssertTrue(popUp.neverChosen)
        XCTAssertEqual(popUp.minutes, 3)
    }

    func testSavingACustomValueFromNeverTurnsAlertsBackOnWithIt() {
        var popUp = PopUp(rule: alertMe, minutes: 3, neverChosen: true)
        popUp.pick(.custom)
        popUp.saveCustom(7)
        XCTAssertFalse(popUp.neverChosen)
        XCTAssertEqual(popUp.minutes, 7)
        XCTAssertEqual(popUp.selection, .custom)
    }

    func testPickingAPresetFromNeverTurnsAlertsBackOnWithIt() {
        var popUp = PopUp(rule: alertMe, minutes: 10, neverChosen: true)
        XCTAssertEqual(popUp.selection, .never)
        popUp.pick(.preset(1))
        XCTAssertFalse(popUp.neverChosen)
        XCTAssertEqual(popUp.minutes, 1)
        XCTAssertEqual(popUp.selection, .preset(1))
    }

    func testPickingNeverKeepsAStored10ForLater() {
        var popUp = PopUp(rule: alertMe, minutes: 10)
        XCTAssertEqual(popUp.selection, .custom)
        popUp.pick(.never)
        XCTAssertEqual(popUp.selection, .never)
        XCTAssertEqual(popUp.minutes, 10)
        popUp.pick(.custom)
        XCTAssertFalse(popUp.neverChosen, "Custom… turns alerts back on with the kept 10 minutes")
        XCTAssertEqual(popUp.minutes, 10)
        XCTAssertEqual(popUp.selection, .custom)
    }

    // MARK: Snooze and Appears, which have no Never

    func testPopUpsWithoutNeverShowAPresetOrCustom() {
        for rule in [snooze, appears] {
            XCTAssertFalse(rule.offersNever)
            XCTAssertEqual(rule.selection(minutes: 5, neverChosen: false, customPicked: false), .preset(5))
            XCTAssertEqual(rule.selection(minutes: 30, neverChosen: false, customPicked: false), .custom, "30 isn't a preset")
            XCTAssertEqual(rule.selection(minutes: 5, neverChosen: false, customPicked: true), .custom)
            XCTAssertEqual(rule.selection(minutes: 5, neverChosen: true, customPicked: false), .preset(5), "no Never to be on")
            XCTAssertTrue(rule.opensAsCustom(minutes: 30, neverChosen: true))
        }
    }

    func testPopUpsWithoutNeverNeverTouchIt() {
        for rule in [snooze, appears] {
            XCTAssertEqual(rule.picking(.preset(3)), MinutesChoice.Pick(customPicked: false, minutes: 3, neverChosen: nil))
            XCTAssertEqual(rule.picking(.custom), MinutesChoice.Pick(customPicked: true, minutes: nil, neverChosen: nil))
            XCTAssertNil(rule.picking(.never).neverChosen)
        }
    }

    func testASnoozeSavedByAnEarlierBuildShowsAsCustomAndStaysCustomOnceSaved() {
        var popUp = PopUp(rule: snooze, minutes: 30)
        XCTAssertEqual(popUp.selection, .custom)
        popUp.saveCustom(5)
        XCTAssertEqual(popUp.selection, .custom, "a custom value matching a preset keeps Custom…")
        popUp.pick(.preset(10))
        XCTAssertEqual(popUp.selection, .preset(10))
        XCTAssertEqual(popUp.minutes, 10)
    }
}
