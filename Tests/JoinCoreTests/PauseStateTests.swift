import Foundation
import Testing
@testable import JoinCore

struct PauseStateTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func activeIsNotPaused() {
        #expect(!PauseState.active.isPaused(at: now))
    }

    @Test func timedPauseExpires() {
        let state = PauseState.until(now.addingTimeInterval(60))
        #expect(state.isPaused(at: now))
        #expect(!state.isPaused(at: now.addingTimeInterval(60)))
        #expect(state.resolved(at: now.addingTimeInterval(61)) == .active)
        #expect(state.resolved(at: now) == state)
    }

    @Test func indefinitePause() {
        #expect(PauseState.indefinitely.isPaused(at: now.addingTimeInterval(1_000_000)))
    }

    @Test func options() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 21, minute: 30))!
        #expect(PauseOption.oneHour.state(from: evening, calendar: calendar) == .until(evening.addingTimeInterval(3600)))
        #expect(
            PauseOption.untilTomorrow.state(from: evening, calendar: calendar)
                == .until(calendar.date(from: DateComponents(year: 2026, month: 10, day: 6))!)
        )
        #expect(PauseOption.untilResumed.state(from: evening, calendar: calendar) == .indefinitely)
    }
}
