import Foundation
import Testing
@testable import JoinCore

/// What a notification says and offers: its title, subtitle and body, its identifier and payload, and the
/// actions of its category.
struct NotificationContentTests {
    private typealias F = MenuBarFixtures

    static let now = F.date(6, 9, 55)
    static let review = Meeting(
        id: "review@1791280800", title: "Design review", start: F.date(6, 10), end: F.date(6, 10, 30),
        calendarTitle: "Work", location: "Conference Room A", joinURL: F.meet
    )

    static func content(_ meeting: Meeting, playsSound: Bool = true, at time: Date = now) -> NotificationContent {
        NotificationContent.meeting(meeting, playsSound: playsSound, now: time, locale: F.us, timeZone: F.calendar.timeZone)
    }

    // MARK: Content

    /// The event's title, its time range as clock times, then the calendar's name and the location as the
    /// full-screen alert shows it. One identifier per meeting, the same every time it's sent.
    @Test func aMeetingsNotification() {
        let content = Self.content(Self.review)
        #expect(content.identifier == .meeting("review@1791280800"))
        #expect(content.identifier.rawValue == "meeting:review@1791280800")
        #expect(content.title == "Design review")
        #expect(F.squash(content.subtitle) == "10:00 – 10:30 AM")
        #expect(content.body == "Work · Conference Room A")
        #expect(content.category == NotificationCategory(offersJoin: true, offersAtEventStart: true))
        #expect(content.playsSound)
        #expect(content.payload == NotificationPayload(meeting: Self.review))
        #expect(NotificationContent.threadIdentifier == "meetings")
        #expect(!Self.content(Self.review, playsSound: false).playsSound)
    }

    /// The body: the calendar's name, then the location, each alone when the other is missing, and the
    /// location as the full-screen alert shows it (lines on one, never only the join link again).
    @Test(arguments: [
        ("both", "Work", "Conference Room A", "Work · Conference Room A"),
        ("no location", "Work", nil, "Work"),
        ("a location that is only the join link", "Work", F.meet.absoluteString, "Work"),
        ("no calendar name", "", "Conference Room A", "Conference Room A"),
        ("a location over two lines", "Personal", "Café Comercial\nGlorieta de Bilbao, 7", "Personal · Café Comercial, Glorieta de Bilbao, 7"),
        ("neither", "", nil, ""),
    ] as [(String, String, String?, String)])
    func body(_ name: String, calendar: String, location: String?, expected: String) {
        var meeting = Self.review
        meeting.calendarTitle = calendar
        meeting.location = location
        #expect(Self.content(meeting).body == expected)
    }

    /// Join only with a link; At event start only while the start is more than a second ahead.
    @Test(arguments: [
        ("a link, before the start", F.meet, now, true, true),
        ("no link", nil, now, false, true),
        ("a second before the start", F.meet, F.date(6, 9, 59, 59), true, false),
        ("at the start", F.meet, F.date(6, 10), true, false),
        ("after the start, no link", nil, F.date(6, 10, 3), false, false),
    ] as [(String, URL?, Date, Bool, Bool)])
    func category(_ name: String, link: URL?, at time: Date, offersJoin: Bool, offersAtEventStart: Bool) {
        var meeting = Self.review
        meeting.joinURL = link
        #expect(Self.content(meeting, at: time).category == NotificationCategory(offersJoin: offersJoin, offersAtEventStart: offersAtEventStart))
    }

    /// Test Notification: the demo event, starting 3 minutes from now, under the demo's own identifier, with a
    /// body that says it's a test where a meeting's has its calendar and location.
    @Test func theTestNotification() {
        let content = NotificationContent.demo(playsSound: true, now: Self.now, locale: F.us, timeZone: F.calendar.timeZone)
        #expect(content.identifier == .demo)
        #expect(content.identifier.rawValue == "demo")
        #expect(content.title == "Hello, I’m a demo event")
        #expect(F.squash(content.subtitle) == "9:58 – 10:58 AM")
        #expect(content.body == "This is a test notification.")
        #expect(content.body == DemoEvent.notificationBody)
        #expect(content.category == NotificationCategory(offersJoin: true, offersAtEventStart: true))
        #expect(content.payload.meetingID == DemoEvent.id)
    }

    /// Test Full-Screen Alert and Test Notification share the event: 3 minutes from now on a whole second, an hour
    /// long, with a link. The test full-screen alert says what it is under its buttons.
    @Test func theDemoEvent() {
        let demo = DemoEvent.meeting(now: Date(timeIntervalSinceReferenceDate: 1000.75))
        #expect(demo.id == "demo")
        #expect(demo.title == MenuBarPresenter.demoEventTitle)
        #expect(demo.start == Date(timeIntervalSinceReferenceDate: 1180))
        #expect(demo.end == Date(timeIntervalSinceReferenceDate: 1180 + 3600))
        #expect(demo.calendarTitle == "Work")
        #expect(demo.location == "Conference Room A")
        #expect(demo.joinURL?.absoluteString == "https://meet.google.com/abc-defg-hij")
        #expect(DemoEvent.fullScreenAlertNote == "This is a test full-screen alert. Press Esc to close it.")
    }

    // MARK: Identifiers and payload

    @Test(arguments: [
        ("meeting:review@1791280800", NotificationIdentifier.meeting("review@1791280800")),
        ("meeting:a:b", .meeting("a:b")),
        ("demo", .demo),
        ("meeting:", nil),
        ("meeting", nil),
        ("Demo", nil),
        ("", nil),
    ] as [(String, NotificationIdentifier?)])
    func identifiers(_ raw: String, expected: NotificationIdentifier?) {
        #expect(NotificationIdentifier(rawValue: raw) == expected)
        if let expected { #expect(expected.rawValue == raw) }
    }

    /// The payload goes into `userInfo` as strings and reads back exactly, link or not, so a response can act
    /// before the calendar is read.
    @Test(arguments: [F.meet, nil] as [URL?])
    func thePayloadReadsBack(link: URL?) throws {
        var meeting = Self.review
        meeting.joinURL = link
        meeting.start = Date(timeIntervalSince1970: 1_791_280_800.25)
        let payload = NotificationPayload(meeting: meeting)
        let userInfo: [AnyHashable: Any] = payload.userInfo
        let read = try #require(NotificationPayload(userInfo: userInfo))
        #expect(read == payload)
        #expect(read.meetingID == meeting.id)
        #expect(read.joinURL == link)
        #expect(read.start == meeting.start)
        #expect(read.end == meeting.end)
    }

    /// A `userInfo` that isn't Join!'s, or is damaged, reads as nothing.
    @Test(arguments: [
        [:],
        ["meetingID": "a", "start": "1", "end": "x"],
        ["meetingID": "a", "start": "1"],
        ["start": "1", "end": "2"],
        ["meetingID": "a", "start": 1.0, "end": 2.0],
    ] as [[String: any Sendable]])
    func aForeignPayloadReadsAsNothing(_ userInfo: [String: any Sendable]) {
        #expect(NotificationPayload(userInfo: userInfo) == nil)
    }

    // MARK: Actions

    static let defaultSnooze = Preferences.defaultSnoozeDurations

    /// Every category, registered at once, each under its own identifier.
    @Test func everyCategory() {
        #expect(NotificationCategory.all.map(\.identifier) == ["meeting.join.atStart", "meeting.join", "meeting.atStart", "meeting"])
    }

    /// Join first, so it stays on a banner, then each snooze duration, then At event start: four at most.
    @Test(arguments: [
        (true, true, ["Join", "Snooze 1 min", "Snooze 5 min", "At event start"], ["join", "snooze.60", "snooze.300", "atEventStart"]),
        (true, false, ["Join", "Snooze 1 min", "Snooze 5 min"], ["join", "snooze.60", "snooze.300"]),
        (false, true, ["Snooze 1 min", "Snooze 5 min", "At event start"], ["snooze.60", "snooze.300", "atEventStart"]),
        (false, false, ["Snooze 1 min", "Snooze 5 min"], ["snooze.60", "snooze.300"]),
    ] as [(Bool, Bool, [String], [String])])
    func actions(offersJoin: Bool, offersAtEventStart: Bool, titles: [String], identifiers: [String]) {
        let actions = NotificationCategory(offersJoin: offersJoin, offersAtEventStart: offersAtEventStart).actions(snoozeDurations: Self.defaultSnooze)
        #expect(actions.map(\.title) == titles)
        #expect(actions.map(\.identifier) == identifiers)
        #expect(actions.count <= 4)
    }

    /// The durations are the Snooze box's, shared with the full-screen alert: two that read the same make one
    /// action, as they make one button on the alert. Each title and identifier is in whole minutes.
    @Test(arguments: [
        ("the defaults", SnoozeDurations(first: 60, second: 300), ["Snooze 1 min", "Snooze 5 min"], ["snooze.60", "snooze.300"]),
        ("both 5 minutes", SnoozeDurations(first: 300, second: 300), ["Snooze 5 min"], ["snooze.300"]),
        ("two that read 1 min", SnoozeDurations(first: 60, second: 80), ["Snooze 1 min"], ["snooze.60"]),
        ("the second first", SnoozeDurations(first: 600, second: 180), ["Snooze 10 min", "Snooze 3 min"], ["snooze.600", "snooze.180"]),
        ("an hour", SnoozeDurations(first: 3600, second: 7200), ["Snooze 1 hr", "Snooze 2 hr"], ["snooze.3600", "snooze.7200"]),
    ] as [(String, SnoozeDurations, [String], [String])])
    func snoozeActions(_ name: String, durations: SnoozeDurations, titles: [String], identifiers: [String]) {
        let actions = NotificationCategory(offersJoin: false, offersAtEventStart: false).actions(snoozeDurations: durations)
        #expect(actions.map(\.title) == titles)
        #expect(actions.map(\.identifier) == identifiers)
    }

    /// Every action of every category reads back as what it does, unique within its category.
    @Test(arguments: NotificationCategory.all)
    func actionsReadBack(_ category: NotificationCategory) {
        let actions = category.actions(snoozeDurations: Self.defaultSnooze)
        #expect(Set(actions.map(\.identifier)).count == actions.count)
        for action in actions {
            #expect(AlertResponse(notificationActionIdentifier: action.identifier) == action.response)
        }
    }

    /// A response from its action's identifier. A click on the notification itself, macOS's close button and
    /// anything else read as nothing, so they do nothing.
    @Test(arguments: [
        ("join", AlertResponse.join),
        ("snooze.60", .snooze(60)),
        ("snooze.3600", .snooze(3600)),
        ("atEventStart", .snoozeUntilStart),
        ("com.apple.UNNotificationDefaultActionIdentifier", nil),
        ("com.apple.UNNotificationDismissActionIdentifier", nil),
        ("snooze.", nil),
        ("snooze.0", nil),
        ("snooze.-60", nil),
        ("snooze.1.5", nil),
        ("Join", nil),
        ("", nil),
    ] as [(String, AlertResponse?)])
    func responses(_ identifier: String, expected: AlertResponse?) {
        #expect(AlertResponse(notificationActionIdentifier: identifier) == expected)
    }

    /// A notification has no Dismiss of Join!'s: macOS's close button stands in for it.
    @Test func closeIsNoAction() {
        #expect(NotificationAction(.close) == nil)
    }
}
