import Testing
@testable import JoinCore

struct MinutesChoiceTests {
    private let alertMe = MinutesChoice(presets: SettingsOptions.leadTimeMinutes, offersNever: true)
    private let snooze = MinutesChoice(presets: SettingsOptions.snoozeMinutes)
    private let appears = MinutesChoice(presets: SettingsOptions.startingSoonMinutes)

    // MARK: Alert me

    @Test func alertMeShowsAPresetWhileAlertsAreOn() {
        for minutes in SettingsOptions.leadTimeMinutes {
            #expect(alertMe.selection(minutes: minutes, neverChosen: false, customPicked: false) == .preset(minutes))
            #expect(!alertMe.opensAsCustom(minutes: minutes, neverChosen: false), "\(minutes) min is a preset")
            #expect(!alertMe.showsCustomRow(minutes: minutes, neverChosen: false, customPicked: false))
        }
    }

    @Test func alertMeShowsNeverWhileAlertsAreOffWhateverTheTime() {
        for minutes in [0, 1, 2, 3, 5, 10, 120] {
            #expect(alertMe.selection(minutes: minutes, neverChosen: true, customPicked: false) == .never, "\(minutes) min")
            #expect(!alertMe.opensAsCustom(minutes: minutes, neverChosen: true), "\(minutes) min")
            #expect(!alertMe.showsCustomRow(minutes: minutes, neverChosen: true, customPicked: false), "\(minutes) min")
        }
    }

    @Test func aStored2Or10ShowsAsCustomOnlyWhileAlertsAreOn() {
        for minutes in [2, 10] {
            #expect(alertMe.opensAsCustom(minutes: minutes, neverChosen: false), "\(minutes) min")
            #expect(alertMe.selection(minutes: minutes, neverChosen: false, customPicked: false) == .custom, "\(minutes) min")
            #expect(alertMe.showsCustomRow(minutes: minutes, neverChosen: false, customPicked: false), "\(minutes) min")
            #expect(alertMe.selection(minutes: minutes, neverChosen: true, customPicked: false) == .never, "\(minutes) min")
        }
    }

    @Test func neverIsKeptApartFromWhenTheEventStartsAndCustom() {
        #expect(MinutesChoice.Item.never != .preset(0))
        #expect(MinutesChoice.Item.never != .custom)
        #expect(MinutesChoice.Item.custom != .preset(0))
        #expect(alertMe.selection(minutes: 0, neverChosen: false, customPicked: false) == .preset(0), "When the event starts isn't Never")
        #expect(alertMe.selection(minutes: 0, neverChosen: true, customPicked: false) == .never)
        let items: Set<MinutesChoice.Item> = Set(SettingsOptions.leadTimeMinutes.map(MinutesChoice.Item.preset) + [.never, .custom])
        #expect(items.count == SettingsOptions.leadTimeMinutes.count + 2, "every item has a tag of its own")
    }

    @Test func customPickedKeepsShowingWhenItsValueMatchesAPresetOrNeverStillHolds() {
        #expect(alertMe.selection(minutes: 3, neverChosen: false, customPicked: true) == .custom)
        #expect(alertMe.showsCustomRow(minutes: 3, neverChosen: false, customPicked: true))
        #expect(alertMe.selection(minutes: 3, neverChosen: true, customPicked: true) == .custom, "Custom… picked from Never")
        #expect(alertMe.showsCustomRow(minutes: 3, neverChosen: true, customPicked: true))
    }

    @Test func pickingAPresetSavesItAndTurnsNeverOff() {
        #expect(alertMe.picking(.preset(5)) == MinutesChoice.Pick(customPicked: false, minutes: 5, neverChosen: false))
        #expect(alertMe.picking(.preset(0)) == MinutesChoice.Pick(customPicked: false, minutes: 0, neverChosen: false))
    }

    @Test func pickingNeverKeepsTheTime() {
        #expect(alertMe.picking(.never) == MinutesChoice.Pick(customPicked: false, minutes: nil, neverChosen: true))
    }

    @Test func pickingCustomKeepsTheTimeAndTurnsNeverOffAtOnce() {
        #expect(alertMe.picking(.custom) == MinutesChoice.Pick(customPicked: true, minutes: nil, neverChosen: false))
        #expect(snooze.picking(.custom) == MinutesChoice.Pick(customPicked: true, minutes: nil, neverChosen: nil),
                "a pop-up without Never leaves it alone")
    }

    @Test func customPickedAfterAChange() {
        // Saved by the pop-up: Custom… stays picked, and a value that isn't a preset picks it.
        #expect(alertMe.customPicked(afterChangeTo: 5, neverChosen: false, customPicked: true, savedHere: true),
                "a custom value that matches a preset stays Custom…")
        #expect(alertMe.customPicked(afterChangeTo: 7, neverChosen: false, customPicked: false, savedHere: true))
        #expect(!alertMe.customPicked(afterChangeTo: 5, neverChosen: false, customPicked: false, savedHere: true), "a preset picked")
        // From elsewhere (Restore Defaults): as on opening the pane.
        #expect(!alertMe.customPicked(afterChangeTo: 3, neverChosen: false, customPicked: true, savedHere: false))
        #expect(alertMe.customPicked(afterChangeTo: 7, neverChosen: false, customPicked: false, savedHere: false))
        #expect(!alertMe.customPicked(afterChangeTo: 7, neverChosen: true, customPicked: true, savedHere: false))
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

    @Test func customFromNeverTurnsAlertsBackOnAtOnceWithTheKeptTime() {
        var popUp = PopUp(rule: alertMe, minutes: 3, neverChosen: true)
        #expect(popUp.selection == .never)
        popUp.pick(.custom)
        #expect(popUp.selection == .custom)
        #expect(!popUp.neverChosen, "what the pop-up shows is what's in effect")
        #expect(popUp.minutes == 3, "the field starts at the kept time")
        popUp.pick(.never)
        popUp.saveCustom(popUp.minutes)   // the row's save as it disappears
        #expect(popUp.selection == .never)
        #expect(popUp.neverChosen)
        #expect(popUp.minutes == 3)
    }

    @Test func savingACustomValueFromNeverTurnsAlertsBackOnWithIt() {
        var popUp = PopUp(rule: alertMe, minutes: 3, neverChosen: true)
        popUp.pick(.custom)
        popUp.saveCustom(7)
        #expect(!popUp.neverChosen)
        #expect(popUp.minutes == 7)
        #expect(popUp.selection == .custom)
    }

    @Test func pickingAPresetFromNeverTurnsAlertsBackOnWithIt() {
        var popUp = PopUp(rule: alertMe, minutes: 10, neverChosen: true)
        #expect(popUp.selection == .never)
        popUp.pick(.preset(1))
        #expect(!popUp.neverChosen)
        #expect(popUp.minutes == 1)
        #expect(popUp.selection == .preset(1))
    }

    @Test func pickingNeverKeepsAStored10ForLater() {
        var popUp = PopUp(rule: alertMe, minutes: 10)
        #expect(popUp.selection == .custom)
        popUp.pick(.never)
        #expect(popUp.selection == .never)
        #expect(popUp.minutes == 10)
        popUp.pick(.custom)
        #expect(!popUp.neverChosen, "Custom… turns alerts back on with the kept 10 minutes")
        #expect(popUp.minutes == 10)
        #expect(popUp.selection == .custom)
    }

    // MARK: Snooze and Starting soon, which have no Never

    @Test func popUpsWithoutNeverShowAPresetOrCustom() {
        for rule in [snooze, appears] {
            #expect(!rule.offersNever)
            #expect(rule.selection(minutes: 5, neverChosen: false, customPicked: false) == .preset(5))
            #expect(rule.selection(minutes: 30, neverChosen: false, customPicked: false) == .custom, "30 isn't a preset")
            #expect(rule.selection(minutes: 5, neverChosen: false, customPicked: true) == .custom)
            #expect(rule.selection(minutes: 5, neverChosen: true, customPicked: false) == .preset(5), "no Never to be on")
            #expect(rule.opensAsCustom(minutes: 30, neverChosen: true))
        }
    }

    @Test func popUpsWithoutNeverNeverTouchIt() {
        for rule in [snooze, appears] {
            #expect(rule.picking(.preset(3)) == MinutesChoice.Pick(customPicked: false, minutes: 3, neverChosen: nil))
            #expect(rule.picking(.custom) == MinutesChoice.Pick(customPicked: true, minutes: nil, neverChosen: nil))
            #expect(rule.picking(.never).neverChosen == nil)
        }
    }

    @Test func aSnoozeSavedByAnEarlierBuildShowsAsCustomAndStaysCustomOnceSaved() {
        var popUp = PopUp(rule: snooze, minutes: 30)
        #expect(popUp.selection == .custom)
        popUp.saveCustom(5)
        #expect(popUp.selection == .custom, "a custom value matching a preset keeps Custom…")
        popUp.pick(.preset(10))
        #expect(popUp.selection == .preset(10))
        #expect(popUp.minutes == 10)
    }
}
