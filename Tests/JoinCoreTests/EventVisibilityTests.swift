import Testing
@testable import JoinCore

struct EventVisibilityTests {
    @Test func thePopUpOffersTheChoicesInOrder() {
        #expect(EventVisibility.allCases == [.showAndAlert, .listOnly, .exclude])
        #expect(EventVisibility.allCases.map(\.title) == ["Show and alert", "Show in the list only", "Exclude"])
    }

    @Test func rawValuesAreWhatPreferencesStore() {
        #expect(EventVisibility.allCases.map(\.rawValue) == ["showAndAlert", "listOnly", "exclude"])
    }

    @Test func orderedByHowMuchItShows() {
        #expect(EventVisibility.exclude < .listOnly)
        #expect(EventVisibility.listOnly < .showAndAlert)
        #expect(min(EventVisibility.showAndAlert, .listOnly) == .listOnly)
        #expect(min(EventVisibility.exclude, .showAndAlert) == .exclude)
    }

    @Test func whatEachChoiceAllows() {
        #expect(EventVisibility.showAndAlert.isListed)
        #expect(EventVisibility.showAndAlert.alerts)
        #expect(EventVisibility.listOnly.isListed)
        #expect(!EventVisibility.listOnly.alerts)
        #expect(!EventVisibility.exclude.isListed)
        #expect(!EventVisibility.exclude.alerts)
    }
}
