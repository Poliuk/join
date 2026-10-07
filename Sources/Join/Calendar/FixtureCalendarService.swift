import Foundation
import JoinCore

/// A fake calendar for checking the UI in a known state, selected with the JOIN_FIXTURE environment
/// variable (`open --env JOIN_FIXTURE=busy build/Join.app`). Fixture runs use their own defaults
/// domain and never schedule alerts, so they can't disturb real settings or cover the screen.
/// Scenarios follow the menu bar design's week: nothing (no more meetings today), later (next
/// meeting later today), busy (one starts in 4 min while another runs), meeting (in a meeting),
/// maybe (a long Maybe block runs while a call you accepted starts in 47 min). Tomorrow's out-of-office
/// block and Focus time the day after have no participants, for the General pane's switch that hides them.
@MainActor
final class FixtureCalendarService: CalendarService {
    static let environmentKey = "JOIN_FIXTURE"
    static let defaultsSuite = "com.poliuk.join.fixture"

    static let scenarios: Set<String> = ["nothing", "later", "busy", "meeting", "maybe", "denied"]

    /// Only a known scenario name turns fixture mode on, so a stray or mistyped value can't
    /// silently replace the real calendar.
    static var scenario: String? {
        guard let value = ProcessInfo.processInfo.environment[environmentKey], !value.isEmpty else { return nil }
        guard scenarios.contains(value) else {
            NSLog("Join: ignoring unknown %@=%@; known scenarios: %@", environmentKey, value, scenarios.sorted().joined(separator: ", "))
            return nil
        }
        return value
    }

    private let name: String
    private let anchor = Date()
    var onChange: (@MainActor () -> Void)?

    init(scenario: String) {
        name = scenario
    }

    var authorization: CalendarAuthorization { name == "denied" ? .denied : .authorized }

    func requestAccess() async -> Bool { authorization == .authorized }

    private static let work = CalendarInfo(id: "work", title: "Work", sourceTitle: "Acme", color: RGBA(hex: "#67CBDD")!)
    private static let personal = CalendarInfo(id: "personal", title: "you@gmail.com", sourceTitle: "you@gmail.com", color: RGBA(hex: "#5CCF97")!)
    private static let holidays = CalendarInfo(id: "holidays", title: "Holidays", sourceTitle: "you@gmail.com", color: RGBA(hex: "#E5A23B")!)
    private static let birthdays = CalendarInfo(id: "birthdays", title: "Birthdays", sourceTitle: "you@gmail.com", color: RGBA(hex: "#B07CE8")!)
    private static let ooo = CalendarInfo(id: "ooo", title: "Out of office", sourceTitle: "Acme", color: RGBA(hex: "#76787F")!)

    func calendars() -> [CalendarInfo] {
        [Self.work, Self.ooo, Self.personal, Self.holidays, Self.birthdays]
    }

    func meetings(from start: Date, to end: Date, calendarIDs: Set<String>?) -> [Meeting] {
        all().filter { meeting in
            meeting.end > start && meeting.start < end && (calendarIDs?.contains(meeting.calendarID) ?? true)
        }
    }

    private func all() -> [Meeting] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: anchor)
        func day(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: offset, to: today)!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
        }
        func minutesFromNow(_ minutes: Double) -> Date {
            let rounded = (anchor.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60
            return Date(timeIntervalSinceReferenceDate: rounded + minutes * 60)
        }
        func meeting(_ id: String, _ title: String, _ start: Date, _ end: Date, _ info: CalendarInfo,
                     location: String? = nil, notes: String? = nil, status: ParticipationStatus = .accepted,
                     participants: Bool = true) -> Meeting {
            Meeting(id: id, title: title, start: start, end: end, calendarID: info.id, calendarTitle: info.title,
                    calendarColor: info.color, location: location, notes: notes, myStatus: status, hasParticipants: participants)
        }
        let meet = "Join with Google Meet: https://meet.google.com/abc-defg-hij"
        let zoom = "https://us06web.zoom.us/j/12345678901?pwd=sample"
        let address = "C. de Ruiz de Alarcón, 23, Retiro, 28014 Madrid, España"

        var today_: [Meeting] = []
        switch name {
        case "later":
            today_ = [meeting("lunch", "Lunch with Lucía", minutesFromNow(135), minutesFromNow(195), Self.personal, location: address),
                      meeting("workshop", "Workshop", minutesFromNow(255), minutesFromNow(525), Self.personal, notes: meet)]
        case "busy":
            today_ = [meeting("workshop", "Workshop", minutesFromNow(-56), minutesFromNow(214), Self.personal, notes: meet),
                      meeting("planning", "Ana/Luis: Product Planning", minutesFromNow(4), minutesFromNow(64), Self.work, location: zoom)]
        case "meeting":
            today_ = [meeting("workshop", "Workshop", minutesFromNow(-80), minutesFromNow(190), Self.personal, notes: meet),
                      meeting("planning", "Ana/Luis: Product Planning", minutesFromNow(-20), minutesFromNow(40), Self.work, location: zoom)]
        case "maybe":
            today_ = [meeting("workshop", "Workshop", minutesFromNow(-18), minutesFromNow(252), Self.personal, notes: meet, status: .tentative),
                      meeting("planning", "Ana/Luis: Product Planning", minutesFromNow(47), minutesFromNow(107), Self.work, location: zoom)]
        default:
            today_ = []
        }

        let later: [Meeting] = [
            meeting("ooo1", "Fuera de la oficina", day(1, 12, 30), day(1, 14, 30), Self.ooo, participants: false),
            meeting("lunch2", "Lunch with Lucía", day(1, 13), day(1, 14), Self.personal, location: address),
            meeting("workshop2", "Workshop", day(1, 15), day(1, 19, 30), Self.personal, notes: meet),
            meeting("planning2", "Ana/Luis: Product Planning", day(1, 16), day(1, 17), Self.work, location: zoom),
            meeting("rev", "Revisión semanal", day(2, 9, 10), day(2, 10, 10), Self.personal, notes: meet),
            meeting("one", "1:1 Marta / Andrés", day(2, 12), day(2, 12, 45), Self.work, notes: meet),
            meeting("focus", "Focus time", day(2, 14), day(2, 15), Self.personal, participants: false),
            meeting("roadmap", "Quarterly Roadmap Review", day(2, 16), day(2, 17), Self.work, location: zoom),
            meeting("crit", "Design Crit", day(3, 10), day(3, 11), Self.work, notes: meet),
        ]
        return (today_ + later).sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }
}
