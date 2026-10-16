import Testing
@testable import JoinCore

/// The rule behind Settings' minutes pop-ups: **Alert me**, the only one with Never, and the snooze buttons'
/// (Starting soon has the same presets as Snooze, and no Never either).
struct MinutesChoiceTests {
    static let alertMe = MinutesChoice(presets: SettingsOptions.leadTimeMinutes, offersNever: true)
    /// Notify me: the same rule as Alert me, Never included, with its own stored time and Never.
    static let notifyMe = MinutesChoice(presets: SettingsOptions.notificationLeadTimeMinutes, offersNever: true)
    static let snooze = MinutesChoice(presets: SettingsOptions.snoozeMinutes)

    /// A pop-up's stored state, and the item it shows.
    struct Shown: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let rule: MinutesChoice
        let minutes: Int
        let neverChosen: Bool
        let customPicked: Bool
        let selection: MinutesChoice.Item

        init(_ name: String, _ rule: MinutesChoice, minutes: Int, never: Bool = false, customPicked: Bool = false, shows selection: MinutesChoice.Item) {
            testDescription = name
            self.rule = rule
            self.minutes = minutes
            neverChosen = never
            self.customPicked = customPicked
            self.selection = selection
        }
    }

    static let shown: [Shown] = [
        // Alert me with alerts on: a preset, or Custom… for a lead time of 2 or 10 minutes from before 1.2.0.
        Shown("When the event starts isn't Never", alertMe, minutes: 0, shows: .preset(0)),
        Shown("1 minute", alertMe, minutes: 1, shows: .preset(1)),
        Shown("3 minutes", alertMe, minutes: 3, shows: .preset(3)),
        Shown("5 minutes", alertMe, minutes: 5, shows: .preset(5)),
        Shown("a stored 2", alertMe, minutes: 2, shows: .custom),
        Shown("a stored 10", alertMe, minutes: 10, shows: .custom),
        // Alerts off: Never, whatever time is kept.
        Shown("Never, keeping When the event starts", alertMe, minutes: 0, never: true, shows: .never),
        Shown("Never, keeping 3", alertMe, minutes: 3, never: true, shows: .never),
        Shown("Never, keeping a stored 2", alertMe, minutes: 2, never: true, shows: .never),
        Shown("Never, keeping a stored 10", alertMe, minutes: 10, never: true, shows: .never),
        // Custom… picked keeps showing, even when its value matches a preset or Never is still set.
        Shown("Custom… picked, at a preset's value", alertMe, minutes: 3, customPicked: true, shows: .custom),
        Shown("Custom… picked from Never", alertMe, minutes: 3, never: true, customPicked: true, shows: .custom),
        // Snooze: a preset or Custom…, with no Never to be on.
        Shown("Snooze at a preset", snooze, minutes: 5, shows: .preset(5)),
        Shown("Snooze at 30, not a preset", snooze, minutes: 30, shows: .custom),
        Shown("Snooze, Custom… picked at a preset's value", snooze, minutes: 5, customPicked: true, shows: .custom),
        Shown("Snooze at a preset, with Never stored", snooze, minutes: 5, never: true, shows: .preset(5)),
        Shown("Snooze at 30, with Never stored", snooze, minutes: 30, never: true, shows: .custom),
    ]

    /// The custom row shows exactly while the pop-up shows Custom…, and with Custom… not picked, the pane
    /// opens on the same item.
    @Test(arguments: shown)
    func popUpShows(_ state: Shown) {
        let rule = state.rule
        #expect(rule.selection(minutes: state.minutes, neverChosen: state.neverChosen, customPicked: state.customPicked) == state.selection)
        #expect(rule.showsCustomRow(minutes: state.minutes, neverChosen: state.neverChosen, customPicked: state.customPicked)
                == (state.selection == .custom))
        if !state.customPicked {
            #expect(rule.opensAsCustom(minutes: state.minutes, neverChosen: state.neverChosen) == (state.selection == .custom))
        }
    }

    /// A preset saves its minutes and turns Never off; Never keeps the time; Custom… keeps it too and turns Never
    /// off at once. A pop-up without Never leaves it alone.
    @Test(arguments: [
        ("Alert me, a preset", alertMe, .preset(5), MinutesChoice.Pick(customPicked: false, minutes: 5, neverChosen: false)),
        ("Alert me, When the event starts", alertMe, .preset(0), MinutesChoice.Pick(customPicked: false, minutes: 0, neverChosen: false)),
        ("Alert me, Never", alertMe, .never, MinutesChoice.Pick(customPicked: false, minutes: nil, neverChosen: true)),
        ("Alert me, Custom…", alertMe, .custom, MinutesChoice.Pick(customPicked: true, minutes: nil, neverChosen: false)),
        ("Snooze, a preset", snooze, .preset(3), MinutesChoice.Pick(customPicked: false, minutes: 3, neverChosen: nil)),
        ("Snooze, Custom…", snooze, .custom, MinutesChoice.Pick(customPicked: true, minutes: nil, neverChosen: nil)),
        ("Snooze, Never, which it doesn't offer", snooze, .never, MinutesChoice.Pick(customPicked: false, minutes: nil, neverChosen: nil)),
    ] as [(String, MinutesChoice, MinutesChoice.Item, MinutesChoice.Pick)])
    func picking(_ name: String, rule: MinutesChoice, item: MinutesChoice.Item, expected: MinutesChoice.Pick) {
        #expect(rule.picking(item) == expected)
    }

    /// Minutes the pop-up saved keep Custom… picked, even at a preset's value, and minutes that aren't a preset
    /// pick it. A change from elsewhere (Restore Defaults) shows as on opening the pane.
    @Test(arguments: [
        ("saved here, Custom… at a preset's value", 5, false, true, true, true),
        ("saved here, not a preset", 7, false, false, true, true),
        ("saved here, a preset picked", 5, false, false, true, false),
        ("from elsewhere, a preset", 3, false, true, false, false),
        ("from elsewhere, not a preset", 7, false, false, false, true),
        ("from elsewhere, with Never chosen", 7, true, true, false, false),
    ])
    func customPickedAfterAChange(_ name: String, minutes: Int, neverChosen: Bool, customPicked: Bool, savedHere: Bool, expected: Bool) {
        #expect(Self.alertMe.customPicked(afterChangeTo: minutes, neverChosen: neverChosen, customPicked: customPicked, savedHere: savedHere)
                == expected)
    }

    // MARK: Stories

    /// The pop-up's own steps, as `SettingsMinutesChoice` takes them.
    struct PopUp {
        let rule: MinutesChoice
        var minutes: Int
        var neverChosen: Bool
        var customPicked: Bool

        init(rule: MinutesChoice, minutes: Int, neverChosen: Bool) {
            self.rule = rule
            self.minutes = minutes
            self.neverChosen = neverChosen
            customPicked = rule.opensAsCustom(minutes: minutes, neverChosen: neverChosen)
        }

        var state: Story.State {
            Story.State(rule.selection(minutes: minutes, neverChosen: neverChosen, customPicked: customPicked), minutes, never: neverChosen)
        }

        mutating func take(_ step: Story.Step) {
            switch step {
            case .pick(let item):
                let pick = rule.picking(item)
                customPicked = pick.customPicked
                if let value = pick.minutes { save(value) }
                if let never = pick.neverChosen { neverChosen = never }
            case .saveCustom(let value):
                save(value)
            }
        }

        private mutating func save(_ value: Int) {
            guard value != minutes else { return }
            minutes = value
            customPicked = rule.customPicked(afterChangeTo: value, neverChosen: neverChosen, customPicked: customPicked, savedHere: true)
        }
    }

    /// Steps through a pop-up, from the state the pane opens on: what it shows after each one.
    struct Story: Sendable, CustomTestStringConvertible {
        enum Step: Sendable {
            case pick(MinutesChoice.Item)
            case saveCustom(Int)
        }

        struct State: Equatable, Sendable {
            let selection: MinutesChoice.Item
            let minutes: Int
            let neverChosen: Bool

            init(_ selection: MinutesChoice.Item, _ minutes: Int, never: Bool = false) {
                self.selection = selection
                self.minutes = minutes
                neverChosen = never
            }
        }

        let testDescription: String
        let rule: MinutesChoice
        let opening: State
        let steps: [(Step, State)]
    }

    static let stories: [Story] = [
        // What the pop-up shows is what's in effect: Custom… turns alerts back on at once, with the kept time in
        // its field, and then with the time saved.
        Story(
            testDescription: "Never, then Custom…, then 7 saved",
            rule: alertMe,
            opening: Story.State(.never, 3, never: true),
            steps: [
                (.pick(.custom), Story.State(.custom, 3)),
                (.saveCustom(7), Story.State(.custom, 7)),
            ]
        ),
        // The lead time is kept while alerts are off.
        Story(
            testDescription: "a stored 10, then Never, then Custom…",
            rule: alertMe,
            opening: Story.State(.custom, 10),
            steps: [
                (.pick(.never), Story.State(.never, 10, never: true)),
                (.pick(.custom), Story.State(.custom, 10)),
            ]
        ),
        // Notify me opens on Never with 5 minutes kept, for new installs and upgrades alike. Custom… turns
        // notifications on at once with that time; a preset turns them on with its own.
        Story(
            testDescription: "Notify me as installed, then Custom…, then Never, then a preset",
            rule: notifyMe,
            opening: Story.State(.never, 5, never: true),
            steps: [
                (.pick(.custom), Story.State(.custom, 5)),
                (.pick(.never), Story.State(.never, 5, never: true)),
                (.pick(.preset(1)), Story.State(.preset(1), 1)),
            ]
        ),
        Story(
            testDescription: "a snooze of 30 from an earlier build, then 5 saved, then the 10 preset",
            rule: snooze,
            opening: Story.State(.custom, 30),
            steps: [
                (.saveCustom(5), Story.State(.custom, 5)),
                (.pick(.preset(10)), Story.State(.preset(10), 10)),
            ]
        ),
    ]

    @Test(arguments: stories)
    func popUpStories(_ story: Story) {
        var popUp = PopUp(rule: story.rule, minutes: story.opening.minutes, neverChosen: story.opening.neverChosen)
        #expect(popUp.state == story.opening)
        for (step, expected) in story.steps {
            popUp.take(step)
            #expect(popUp.state == expected, "after \(step)")
        }
    }
}
