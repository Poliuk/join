import Testing
@testable import JoinCore

/// General's **Shows** pop-up, stored as the two older switches.
struct MenuBarDisplayTests {
    /// Show next event off wins over titles: the icon alone, whatever the title switch says.
    @Test(arguments: [
        (false, false, MenuBarDisplay.iconOnly),
        (false, true, .iconOnly),
        (true, false, .time),
        (true, true, .titleAndTime),
    ])
    func mapsTheTwoStoredPreferences(showsNextEvent: Bool, showsTitles: Bool, expected: MenuBarDisplay) {
        #expect(MenuBarDisplay(showsNextEvent: showsNextEvent, showsTitles: showsTitles) == expected)
    }

    @Test func titles() {
        #expect(MenuBarDisplay.allCases.map(\.title) == ["Icon only", "Time until next event", "Title and time until next event"])
    }
}
