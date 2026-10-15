import Foundation
import Testing
@testable import JoinCore

struct MeetingTests {
    /// Dismissals are saved by this id (1.2.0's too), and `seriesID` is the part before "@": a new format
    /// would orphan them.
    @Test func occurrenceIDIncludesStart() {
        #expect(Meeting.occurrenceID(eventIdentifier: "evt", start: Date(timeIntervalSince1970: 1_800_000_000)) == "evt@1800000000")
    }

    /// A meeting from 10:00 to 11:00 is on from its start and over at its end, and always exactly one of
    /// upcoming, on and over. Every presenter, the alert scheduler and the dismissals' pruning go by these.
    @Test(arguments: [
        ("a second before its start", -1, false, true, false),
        ("at its start", 0, true, false, false),
        ("halfway", 30 * 60, true, false, false),
        ("a second before its end", 60 * 60 - 1, true, false, false),
        ("at its end", 60 * 60, false, false, true),
    ] as [(String, TimeInterval, Bool, Bool, Bool)])
    func onFromItsStartUntilItsEnd(_ name: String, sinceStart: TimeInterval, isOngoing: Bool, isUpcoming: Bool, hasEnded: Bool) {
        let start = MenuBarFixtures.date(6, 10)
        let meeting = Meeting(id: "call", title: "Call", start: start, end: start.addingTimeInterval(60 * 60))
        let now = start.addingTimeInterval(sinceStart)
        #expect(meeting.isOngoing(at: now) == isOngoing)
        #expect(meeting.isUpcoming(at: now) == isUpcoming)
        #expect(meeting.hasEnded(at: now) == hasEnded)
    }
}
