import XCTest
@testable import JoinCore

final class MeetingFilterTests: XCTestCase {
    func testAllDayEventsAreExcluded() {
        XCTAssertFalse(MeetingFilter.shouldInclude(isAllDay: true, isCanceled: false, myStatus: .accepted))
    }

    func testCanceledEventsAreExcluded() {
        XCTAssertFalse(MeetingFilter.shouldInclude(isAllDay: false, isCanceled: true, myStatus: .accepted))
    }

    func testDeclinedEventsAreExcluded() {
        XCTAssertFalse(MeetingFilter.shouldInclude(isAllDay: false, isCanceled: false, myStatus: .declined))
    }

    func testTentativeAndUnknownAreIncluded() {
        XCTAssertTrue(MeetingFilter.shouldInclude(isAllDay: false, isCanceled: false, myStatus: .tentative))
        XCTAssertTrue(MeetingFilter.shouldInclude(isAllDay: false, isCanceled: false, myStatus: .unknown))
    }

    // MARK: Events with no participants

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func meeting(
        _ id: String,
        participants: Bool,
        status: ParticipationStatus = .accepted,
        outOfOffice: Bool = false
    ) -> Meeting {
        Meeting(
            id: id, title: id, start: start, end: start.addingTimeInterval(3600),
            myStatus: status, hasParticipants: participants, isOutOfOffice: outOfOffice
        )
    }

    func testMeetingsHaveParticipantsUnlessToldOtherwise() {
        XCTAssertTrue(Meeting(id: "call", title: "Call", start: start, end: start.addingTimeInterval(1800)).hasParticipants)
        XCTAssertFalse(meeting("focus", participants: false).hasParticipants)
    }

    func testEveryEventIsVisibleWhileTheSwitchIsOn() {
        let meetings = [
            meeting("focus", participants: false),
            meeting("standup", participants: true),
            meeting("ooo", participants: false, outOfOffice: true),
        ]
        XCTAssertEqual(MeetingFilter.visible(meetings, showsEventsWithoutParticipants: true), meetings)
    }

    func testEventsWithoutParticipantsAreLeftOutWhenTheSwitchIsOff() {
        let meetings = [
            meeting("standup", participants: true),
            meeting("focus", participants: false),
            meeting("review", participants: true),
            meeting("reminder", participants: false),
        ]
        let visible = MeetingFilter.visible(meetings, showsEventsWithoutParticipants: false)
        XCTAssertEqual(visible.map(\.id), ["standup", "review"], "keeps the order")
        XCTAssertEqual(MeetingFilter.visible([], showsEventsWithoutParticipants: false), [])
    }

    func testOutOfOfficeEventsWithoutParticipantsAreLeftOutWhateverTheOutOfOfficeOptions() {
        let solo = meeting("ooo-solo", participants: false, outOfOffice: true)
        let shared = meeting("ooo-team", participants: true, outOfOffice: true)
        let visible = MeetingFilter.visible([solo, shared], showsEventsWithoutParticipants: false)
        XCTAssertEqual(visible, [shared], "an out-of-office event someone else is on stays, still marked out of office")

        // The out-of-office rule runs on what's visible, so no out-of-office option brings the solo one back.
        XCTAssertEqual(MeetingFilter.alertable(visible, alertForOutOfOffice: true), [shared])
        XCTAssertEqual(MeetingFilter.alertable(visible, alertForOutOfOffice: false), [])
    }

    func testAlertableLeavesOutOfOfficeOutUnlessAsked() {
        let call = meeting("call", participants: true)
        let away = meeting("away", participants: true, outOfOffice: true)
        XCTAssertEqual(MeetingFilter.alertable([call, away], alertForOutOfOffice: false), [call])
        XCTAssertEqual(MeetingFilter.alertable([call, away], alertForOutOfOffice: true), [call, away], "keeps the order")
    }

    func testYourAnswerDoesNotChangeWhatTheSwitchHides() {
        for status in [ParticipationStatus.accepted, .tentative, .unknown] {
            let meetings = [meeting("call", participants: true, status: status), meeting("hold", participants: false, status: status)]
            XCTAssertEqual(MeetingFilter.visible(meetings, showsEventsWithoutParticipants: false).map(\.id), ["call"], "\(status)")
            XCTAssertEqual(MeetingFilter.visible(meetings, showsEventsWithoutParticipants: true).map(\.id), ["call", "hold"], "\(status)")
        }
        // Declined events never reach the list, so turning the switch on can't bring them back either.
        XCTAssertFalse(MeetingFilter.shouldInclude(isAllDay: false, isCanceled: false, myStatus: .declined))
    }

    func testOccurrenceIDIncludesStart() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(Meeting.occurrenceID(eventIdentifier: "evt", start: start), "evt@1800000000")
        XCTAssertNotEqual(
            Meeting.occurrenceID(eventIdentifier: "evt", start: start),
            Meeting.occurrenceID(eventIdentifier: "evt", start: start.addingTimeInterval(86400))
        )
    }
}
