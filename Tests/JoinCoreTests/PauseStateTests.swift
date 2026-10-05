import XCTest
@testable import JoinCore

final class PauseStateTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testActiveIsNotPaused() {
        XCTAssertFalse(PauseState.active.isPaused(at: now))
    }

    func testTimedPauseExpires() {
        let state = PauseState.until(now.addingTimeInterval(60))
        XCTAssertTrue(state.isPaused(at: now))
        XCTAssertFalse(state.isPaused(at: now.addingTimeInterval(60)))
        XCTAssertEqual(state.resolved(at: now.addingTimeInterval(61)), .active)
        XCTAssertEqual(state.resolved(at: now), state)
    }

    func testIndefinitePause() {
        XCTAssertTrue(PauseState.indefinitely.isPaused(at: now.addingTimeInterval(1_000_000)))
        XCTAssertNil(PauseState.indefinitely.endsAt)
    }

    func testOptions() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 21, minute: 30))!
        XCTAssertEqual(PauseOption.oneHour.state(from: evening, calendar: calendar), .until(evening.addingTimeInterval(3600)))
        XCTAssertEqual(
            PauseOption.untilTomorrow.state(from: evening, calendar: calendar),
            .until(calendar.date(from: DateComponents(year: 2026, month: 10, day: 6))!)
        )
        XCTAssertEqual(PauseOption.untilResumed.state(from: evening, calendar: calendar), .indefinitely)
    }

    func testRoundTripsThroughJSON() throws {
        for state in [PauseState.active, .until(now), .indefinitely] {
            XCTAssertEqual(try JSONDecoder().decode(PauseState.self, from: JSONEncoder().encode(state)), state)
        }
    }
}
