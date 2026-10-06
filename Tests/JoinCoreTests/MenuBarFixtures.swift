import Foundation
@testable import JoinCore

/// The week drawn in the menu bar design artboards (Monday 5 – Thursday 8 October 2026), in UTC so the
/// tests don't depend on the machine's time zone.
enum MenuBarFixtures {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static let us = Locale(identifier: "en_US")
    static let gb = Locale(identifier: "en_GB")

    static func date(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }

    static let meet = URL(string: "https://meet.google.com/abc-defg-hij")!

    static let outOfOffice = Meeting(id: "ooo", title: "Out of office", start: date(6, 12, 30), end: date(6, 14, 30), isOutOfOffice: true)
    static let lunch = Meeting(
        id: "lunch", title: "Lunch with Lucía", start: date(6, 13), end: date(6, 14),
        location: "C. de Ruiz de Alarcón, 23, Retiro, 28014 Madrid, España"
    )
    static let workshop = Meeting(id: "val", title: "Workshop", start: date(6, 15), end: date(6, 19, 30), joinURL: meet)
    static let planning = Meeting(id: "plan", title: "Ana/Luis: Product Planning", start: date(6, 16), end: date(6, 17), joinURL: meet)
    static let review = Meeting(id: "rev", title: "Revisión semanal", start: date(7, 9, 10), end: date(7, 10, 10), joinURL: meet)
    static let oneOnOne = Meeting(id: "one", title: "1:1 Marta / Andrés", start: date(7, 12), end: date(7, 12, 45), joinURL: meet)
    static let roadmap = Meeting(id: "road", title: "Quarterly Roadmap Review", start: date(7, 16), end: date(7, 17), joinURL: meet)
    static let thursday = Meeting(id: "thu", title: "Design Crit", start: date(8, 10), end: date(8, 11), joinURL: meet)

    static let week = [outOfOffice, lunch, workshop, planning, review, oneOnOne, roadmap, thursday]
    static var alertable: [Meeting] { week.filter { !$0.isOutOfOffice } }

    /// A week after the artboards' Monday, on the same weekday: the furthest the store looks ahead.
    static let nextMonday = Meeting(id: "weekly", title: "Weekly", start: date(12, 9), end: date(12, 9, 30), joinURL: meet)
    static let sunday = Meeting(id: "sun", title: "Brunch", start: date(11, 9), end: date(11, 10))

    /// Foundation formats times with narrow no-break spaces, and the spacing varies by OS: normalize before comparing.
    static func squash(_ text: String?) -> String? {
        text?.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    /// Foundation's own rendering of a date template on a fixture day. Locale data changes punctuation between
    /// macOS releases (en_GB "EEEdMMM" is "Tue, 6 Oct" on macOS 14 and "Tue 6 Oct" later), so expectations built
    /// with this pin which template, day and locale our code uses, not one release's punctuation.
    static func formatted(_ template: String, day: Int, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return squash(formatter.string(from: date(day, 12)))!
    }
}
