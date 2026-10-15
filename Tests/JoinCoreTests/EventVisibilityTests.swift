import Testing
@testable import JoinCore

struct EventVisibilityTests {
    /// The pop-up's choices, in its order: the words it shows ("Exclude" is the user's) and the raw value
    /// Preferences stores. What each one lets an event do is `MeetingFilterTests`' table.
    static let choices: [(EventVisibility, String, String)] = [
        (.showAndAlert, "Show and alert", "showAndAlert"),
        (.listOnly, "Show in the list only", "listOnly"),
        (.exclude, "Exclude", "exclude"),
    ]

    @Test func thePopUpOffersTheChoicesInOrder() {
        #expect(EventVisibility.allCases == Self.choices.map(\.0))
    }

    @Test(arguments: choices)
    func titleAndStoredValue(_ choice: EventVisibility, title: String, rawValue: String) {
        #expect(choice.title == title)
        #expect(choice.rawValue == rawValue)
    }
}
