import Foundation
import Testing
@testable import JoinCore

struct PauseStateTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let inAMinute = PauseState.until(now.addingTimeInterval(60))
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    static let evening = utc.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 21, minute: 30))!

    /// A timed pause ends exactly at its instant, and then collapses to `.active`.
    @Test(arguments: [
        ("active", PauseState.active, 0, false, PauseState.active),
        ("a timed pause before its end", inAMinute, 0, true, inAMinute),
        ("a timed pause at its end", inAMinute, 60, false, .active),
        ("an indefinite pause, much later", .indefinitely, 1_000_000, true, .indefinitely),
    ] as [(String, PauseState, TimeInterval, Bool, PauseState)])
    func pauseStateAtTime(_ name: String, _ state: PauseState, after offset: TimeInterval, isPaused: Bool, resolved: PauseState) {
        let time = Self.now.addingTimeInterval(offset)
        #expect(state.isPaused(at: time) == isPaused)
        #expect(state.resolved(at: time) == resolved)
    }

    /// The bell menu's choices: "until tomorrow" means the next midnight in the calendar.
    @Test(arguments: [
        (PauseOption.oneHour, "Pause for 1 hour", PauseState.until(evening.addingTimeInterval(3600))),
        (.untilTomorrow, "Pause until tomorrow", .until(utc.date(from: DateComponents(year: 2026, month: 10, day: 6))!)),
        (.untilResumed, "Pause until I resume", .indefinitely),
    ] as [(PauseOption, String, PauseState)])
    func options(_ option: PauseOption, title: String, state: PauseState) {
        #expect(option.title == title)
        #expect(option.state(from: Self.evening, calendar: Self.utc) == state)
    }

    /// The bell's tooltip and VoiceOver label, and the menu's first item while paused: "alerts" covers both
    /// kinds, since a pause stops the full-screen alert and the notification alike. The menu's choices keep
    /// their words.
    @Test func theBellSaysAlerts() {
        #expect(PauseCopy.pauseTitle == "Pause alerts")
        #expect(PauseCopy.resumeTitle == "Resume alerts")
    }

    /// A pause survives quitting and relaunching (PRODUCT_BRIEF #9): `AlertCoordinator` stores it as JSON and reads
    /// it back at launch. What builds since 1.0.0 stored still reads, and what this one stores reads back the same.
    @Test(arguments: [
        (PauseState.until(now.addingTimeInterval(3600)), #"{"until":{"_0":821696400}}"#),
        (.indefinitely, #"{"indefinitely":{}}"#),
        (.active, #"{"active":{}}"#),
    ] as [(PauseState, String)])
    func aPauseSurvivesARelaunch(_ state: PauseState, stored: String) throws {
        #expect(try JSONDecoder().decode(PauseState.self, from: Data(stored.utf8)) == state)
        let relaunched = try JSONDecoder().decode(PauseState.self, from: JSONEncoder().encode(state))
        #expect(relaunched == state)
    }
}
