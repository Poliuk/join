import Foundation
import Testing
@testable import JoinCore

/// What a notification card says: its title, countdown, time range and third line, what VoiceOver hears, its
/// menu, and how cards stack on a screen.
struct NotificationCardTests {
    private typealias F = MenuBarFixtures

    static let now = F.date(6, 9, 55)
    static let review = Meeting(
        id: "review@1791280800", title: "Design review", start: F.date(6, 10), end: F.date(6, 10, 30),
        calendarTitle: "Work", location: "Conference Room A", joinURL: F.meet
    )

    static func card(_ meeting: Meeting = review) -> NotificationCard {
        NotificationCard.meeting(meeting, locale: F.us, timeZone: F.calendar.timeZone)
    }

    static let testCard = NotificationCard.test(now: now, locale: F.us, timeZone: F.calendar.timeZone)

    // MARK: Content

    /// The event's title, its time range, then the location as the full-screen alert shows it, on a card 76 pt
    /// tall; one card per meeting, under the meeting's id.
    @Test func aMeetingsCard() {
        let card = Self.card()
        #expect(card.id == "review@1791280800")
        #expect(card.title == "Design review")
        #expect(F.squash(card.timeRange) == "10:00 – 10:30 AM")
        #expect(card.detail == .location("Conference Room A"))
        #expect(card.detail?.text == "Conference Room A")
        #expect(card.joinURL == F.meet)
        #expect(!card.isTest)
        #expect(card.height == 76)
        #expect(NotificationCard.width == 380)
    }

    /// The third line: the location as the full-screen alert shows it (lines on one, never only the join link
    /// again), and never the calendar's name, which is often the user's email address. Without one the card is
    /// 60 pt tall.
    @Test(arguments: [
        ("a location", "Work", "Conference Room A", "Conference Room A"),
        ("a calendar named after an email address", "someone@example.com", "Conference Room A", "Conference Room A"),
        ("no location", "Work", nil, nil),
        ("a location that is only the join link", "Work", F.meet.absoluteString, nil),
        ("a location over two lines", "Personal", "Café Comercial\nGlorieta de Bilbao, 7", "Café Comercial, Glorieta de Bilbao, 7"),
        ("neither", "", nil, nil),
    ] as [(String, String, String?, String?)])
    func theThirdLine(_ name: String, calendar: String, location: String?, expected: String?) {
        var meeting = Self.review
        meeting.calendarTitle = calendar
        meeting.location = location
        let card = Self.card(meeting)
        #expect(card.detail == expected.map(NotificationCard.Detail.location))
        #expect(card.height == (expected == nil ? 60 : 76))
    }

    /// Test Notification's card: the demo event, starting 3 minutes from now, with a note that says it's a test
    /// where a meeting's card has its location, and the demo event's link.
    @Test func theTestCard() {
        let card = Self.testCard
        #expect(card.isTest)
        #expect(card.id == DemoEvent.id)
        #expect(card.title == "Hello, I’m a demo event")
        #expect(F.squash(card.timeRange) == "9:58 – 10:58 AM")
        #expect(card.detail == .note("This is a test notification."))
        #expect(card.detail?.text == DemoEvent.notificationNote)
        #expect(card.joinURL == DemoEvent.joinURL)
        #expect(card.height == 76)
        #expect(card.countdown(now: Self.now).text == "Starts in 3 min")
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

    // MARK: Countdown

    /// The time line's first part, its tone and the Join button's title, `offset` seconds from the start of a
    /// half-hour meeting. Whole minutes rounded up before the start, so the last minute reads "Starts in 1 min";
    /// "Starting now" for the first minute after it; then whole minutes rounded down in the warning orange,
    /// past the end too, since a card whose meeting ends is withdrawn.
    @Test(arguments: [
        (-300, "Starts in 5 min", NotificationCard.Countdown.Tone.accent, "Join", "starts in 5 minutes"),
        (-300.03, "Starts in 5 min", .accent, "Join", "starts in 5 minutes"),
        (-299.5, "Starts in 5 min", .accent, "Join", "starts in 5 minutes"),
        (-240.5, "Starts in 5 min", .accent, "Join", "starts in 5 minutes"),
        (-240, "Starts in 4 min", .accent, "Join", "starts in 4 minutes"),
        (-60, "Starts in 1 min", .accent, "Join", "starts in 1 minute"),
        (-0.5, "Starts in 1 min", .accent, "Join", "starts in 1 minute"),
        (-3600, "Starts in 1 hr", .accent, "Join", "starts in 1 hour"),
        (-5400, "Starts in 1 hr 30 min", .accent, "Join", "starts in 1 hour 30 minutes"),
        (-7200, "Starts in 2 hr", .accent, "Join", "starts in 2 hours"),
        (0, "Starting now", .accent, "Join now", "starting now"),
        (59, "Starting now", .accent, "Join now", "starting now"),
        (60, "Started 1 min ago", .warning, "Join now", "started 1 minute ago"),
        (3 * 60 + 30, "Started 3 min ago", .warning, "Join now", "started 3 minutes ago"),
        (3900, "Started 1 hr 5 min ago", .warning, "Join now", "started 1 hour 5 minutes ago"),
    ] as [(TimeInterval, String, NotificationCard.Countdown.Tone, String, String)])
    func theCountdown(offset: TimeInterval, text: String, tone: NotificationCard.Countdown.Tone, joinTitle: String, spoken: String) {
        let countdown = Self.card().countdown(now: Self.review.start.addingTimeInterval(offset))
        #expect(countdown.text == text)
        #expect(countdown.tone == tone)
        #expect(countdown.joinTitle == joinTitle)
        #expect(countdown.spokenText == spoken)
    }

    // MARK: Accessibility

    /// The text reads as one element: title, countdown, time range with "to" for the dash, then the third line.
    @Test(arguments: [
        ("a location", review, "Design review, starts in 5 minutes, 10:00 to 10:30 AM, Conference Room A"),
        ("no location", Meeting(id: "a", title: "Stand-up", start: F.date(6, 10), end: F.date(6, 10, 15)), "Stand-up, starts in 5 minutes, 10:00 to 10:15 AM"),
    ] as [(String, Meeting, String)])
    func theTextReadsAsOneElement(_ name: String, meeting: Meeting, expected: String) {
        #expect(F.squash(Self.card(meeting).accessibilityLabel(now: Self.now)) == expected)
    }

    @Test func theTestCardReadsAsOneElement() {
        #expect(F.squash(Self.testCard.accessibilityLabel(now: Self.now))
                == "Hello, I’m a demo event, starts in 3 minutes, 9:58 to 10:58 AM, This is a test notification.")
    }

    /// The dash of any time range, with or without spaces around it, reads "to".
    @Test(arguments: [
        ("10:00 – 10:30 AM", "10:00 to 10:30 AM"),
        ("10:00–10:30", "10:00 to 10:30"),
        ("11:30 PM – 12:30 AM", "11:30 PM to 12:30 AM"),
        ("Mon 9:00 AM – Wed 5:00 PM", "Mon 9:00 AM to Wed 5:00 PM"),
    ])
    func theDashReadsTo(_ range: String, spoken: String) {
        #expect(NotificationCard.spokenRange(range) == spoken)
    }

    /// Posted as the card appears, in each state.
    @Test(arguments: [
        (-300, "Join!: Design review starts in 5 minutes."),
        (-30, "Join!: Design review starts in 1 minute."),
        (10, "Join!: Design review is starting now."),
        (180, "Join!: Design review started 3 minutes ago."),
    ] as [(TimeInterval, String)])
    func theAnnouncement(offset: TimeInterval, expected: String) {
        #expect(Self.card().announcement(now: Self.review.start.addingTimeInterval(offset)) == expected)
    }

    /// The buttons' VoiceOver names carry the title; their help tags show while Join! isn't active too.
    @Test func theButtons() {
        let card = Self.card()
        #expect(card.joinAccessibilityLabel == "Join video call: Design review")
        #expect(card.menuAccessibilityLabel == "Snooze or dismiss Design review")
        #expect(card.closeAccessibilityLabel == "Dismiss notification: Design review")
        #expect(NotificationCard.joinHelp == "Opens the video call. No more alerts for this event.")
        #expect(NotificationCard.menuHelp == "Snooze or dismiss")
        #expect(NotificationCard.closeHelp == "Dismiss")
        #expect(NotificationCard.snoozeMenuTitle == "Snooze")
        #expect(NotificationCard.windowTitle == "Join! notification")
    }

    // MARK: Menu

    static func menu(
        _ card: NotificationCard? = nil,
        durations: SnoozeDurations = Preferences.defaultSnoozeDurations,
        fullScreenAlertsEnabled: Bool = true,
        at time: Date = now
    ) -> NotificationMenu {
        NotificationMenu(
            for: card ?? Self.card(), snoozeDurations: durations, fullScreenAlertsEnabled: fullScreenAlertsEnabled,
            now: time, locale: F.us, timeZone: F.calendar.timeZone
        )
    }

    /// The Snooze box's two times, then At event start while the start is ahead, then, after the separator,
    /// Dismiss: titles, what VoiceOver says and the help tags.
    @Test func theMenu() {
        let menu = Self.menu()
        #expect(menu.snoozes.map(\.title) == ["Snooze 1 min", "Snooze 5 min", "At event start"])
        #expect(menu.snoozes.map(\.response) == [.snooze(60), .snooze(300), .snoozeUntilStart])
        #expect(menu.snoozes.map { F.squash($0.accessibilityLabel) } == [
            "Snooze 1 minute", "Snooze 5 minutes", "Snooze until the event starts at 10:00 AM",
        ])
        #expect(menu.snoozes.map { F.squash($0.help) } == [nil, nil, "Comes back at 10:00 AM."])
        #expect(menu.dismiss.title == "Dismiss")
        #expect(menu.dismiss.accessibilityLabel == "Dismiss")
        #expect(menu.dismiss.response == .close)
        #expect(menu.dismiss.help == "Closes this notification. The full-screen alert still comes at its time.")
        #expect(NotificationMenu.minimumWidth == 180)
        #expect(NotificationMenu.gap == 4)
    }

    /// At event start only while the start is more than a second ahead, decided as the menu opens.
    @Test(arguments: [
        ("five minutes before", now, true),
        ("1.5 s before", F.date(6, 10).addingTimeInterval(-1.5), true),
        ("a second before", F.date(6, 9, 59, 59), false),
        ("at the start", F.date(6, 10), false),
        ("after the start", F.date(6, 10, 3), false),
    ] as [(String, Date, Bool)])
    func atEventStart(_ name: String, at time: Date, offered: Bool) {
        let responses = Self.menu(at: time).snoozes.map(\.response)
        #expect(responses.contains(.snoozeUntilStart) == offered)
        #expect(responses.prefix(2) == [.snooze(60), .snooze(300)])
    }

    /// The times are the Snooze box's, shared with the full-screen alert: two that read the same make one item,
    /// as they make one button on the alert.
    @Test(arguments: [
        ("the defaults", SnoozeDurations(first: 60, second: 300), ["Snooze 1 min", "Snooze 5 min"], ["Snooze 1 minute", "Snooze 5 minutes"]),
        ("both 5 minutes", SnoozeDurations(first: 300, second: 300), ["Snooze 5 min"], ["Snooze 5 minutes"]),
        ("two that read 1 min", SnoozeDurations(first: 60, second: 80), ["Snooze 1 min"], ["Snooze 1 minute"]),
        ("the second first", SnoozeDurations(first: 600, second: 180), ["Snooze 10 min", "Snooze 3 min"], ["Snooze 10 minutes", "Snooze 3 minutes"]),
        ("custom", SnoozeDurations(first: 900, second: 3600), ["Snooze 15 min", "Snooze 1 hr"], ["Snooze 15 minutes", "Snooze 1 hour"]),
    ] as [(String, SnoozeDurations, [String], [String])])
    func snoozeItems(_ name: String, durations: SnoozeDurations, titles: [String], spoken: [String]) {
        let snoozes = Self.menu(durations: durations, at: F.date(6, 10, 1)).snoozes
        #expect(snoozes.map(\.title) == titles)
        #expect(snoozes.map(\.accessibilityLabel) == spoken)
    }

    /// Dismiss's help tag says the full-screen alert still comes only while Alert me has a time, and never on
    /// the test card, which has none.
    @Test(arguments: [
        ("Alert me has a time", false, true, "Closes this notification. The full-screen alert still comes at its time."),
        ("Alert me is Never", false, false, "Closes this notification."),
        ("the test card", true, true, "Closes this notification."),
    ] as [(String, Bool, Bool, String)])
    func dismissHelp(_ name: String, isTest: Bool, fullScreenAlertsEnabled: Bool, help: String) {
        let card = isTest ? Self.testCard : Self.card()
        #expect(Self.menu(card, fullScreenAlertsEnabled: fullScreenAlertsEnabled).dismiss.help == help)
    }

    // MARK: Stacking

    static func stacked(_ id: String, _ title: String, starts start: Date) -> NotificationCard {
        card(Meeting(id: id, title: title, start: start, end: start.addingTimeInterval(1800)))
    }

    static let first = stacked("a", "Stand-up", starts: F.date(6, 10))
    static let second = stacked("b", "Design review", starts: F.date(6, 10, 30))
    static let secondTwin = stacked("c", "Design review", starts: F.date(6, 10, 30))
    static let secondByTitle = stacked("d", "Budget", starts: F.date(6, 10, 30))
    static let third = stacked("e", "Planning", starts: F.date(6, 11))
    static let fourth = stacked("f", "Retro", starts: F.date(6, 12))

    /// Soonest on top; meetings that start together by title, then by id.
    @Test func theOrder() {
        let ordered = NotificationStack.ordered([Self.fourth, Self.secondTwin, Self.second, Self.first, Self.secondByTitle, Self.third])
        #expect(ordered.map(\.id) == ["a", "d", "b", "c", "e", "f"])
    }

    /// At most three cards on a screen; the rest wait their turn, soonest first, and a card on screen keeps its
    /// slot even when a sooner meeting's card comes later.
    @Test(arguments: [
        ("nothing on screen", ["a", "b", "e", "f", "d"], [], ["a", "d", "b"], ["e", "f"]),
        ("three or fewer", ["e", "a"], [], ["a", "e"], []),
        ("a sooner card comes later", ["a", "b", "e", "f"], ["b", "e", "f"], ["b", "e", "f"], ["a"]),
        ("a slot frees for the soonest waiting", ["a", "b", "f", "d"], ["b", "f"], ["a", "b", "f"], ["d"]),
        ("one on screen, the rest in order", ["f", "a", "b", "e"], ["f"], ["a", "b", "f"], ["e"]),
        ("none due", [], ["a"], [], []),
    ] as [(String, [String], Set<String>, [String], [String])])
    func theLimit(_ name: String, due: [String], onScreen: Set<String>, shown: [String], waiting: [String]) {
        let cards = [Self.first, Self.second, Self.secondByTitle, Self.third, Self.fourth]
        let byID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        let arrangement = NotificationStack.arrange(due.compactMap { byID[$0] }, shown: onScreen)
        #expect(arrangement.shown.map(\.id) == shown)
        #expect(arrangement.waiting.map(\.id) == waiting)
        #expect(NotificationStack.maximumPerScreen == 3)
    }

    /// Cards stack downward 8 pt apart, each as tall as its lines.
    @Test(arguments: [
        ([], []),
        ([60], [0]),
        ([60, 76, 60], [0, 68, 152]),
        ([76, 76], [0, 84]),
    ] as [([Double], [Double])])
    func theOffsets(heights: [Double], expected: [Double]) {
        #expect(NotificationStack.offsets(heights: heights) == expected)
    }

    /// 12 pt under the menu bar, measured the same whether it's shown, auto-hidden or in a full-screen Space, and
    /// under the notch.
    @Test(arguments: [
        ("the menu bar shown", 0, 24, 24, 36),
        ("auto-hidden or a full-screen Space", 0, 24, 0, 36),
        ("a taller menu bar", 0, 24, 33, 45),
        ("the notch", 38, 24, 38, 50),
    ] as [(String, Double, Double, Double, Double)])
    func theTopInset(_ name: String, safeAreaTop: Double, menuBarThickness: Double, reservedTop: Double, expected: Double) {
        #expect(NotificationStack.topInset(safeAreaTop: safeAreaTop, menuBarThickness: menuBarThickness, reservedTop: reservedTop) == expected)
        #expect(NotificationStack.screenMargin == 12)
        #expect(NotificationStack.spacing == 8)
    }
}
