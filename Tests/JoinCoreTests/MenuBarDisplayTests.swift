import Testing
@testable import JoinCore

struct MenuBarDisplayTests {
    @Test func mapsTheTwoStoredPreferences() {
        #expect(MenuBarDisplay(showsNextEvent: false, showsTitles: false) == .iconOnly)
        #expect(MenuBarDisplay(showsNextEvent: false, showsTitles: true) == .iconOnly)
        #expect(MenuBarDisplay(showsNextEvent: true, showsTitles: false) == .time)
        #expect(MenuBarDisplay(showsNextEvent: true, showsTitles: true) == .titleAndTime)
    }

    @Test func titles() {
        #expect(MenuBarDisplay.allCases.map(\.title) == ["Icon only", "Time until next event", "Title and time until next event"])
    }
}
