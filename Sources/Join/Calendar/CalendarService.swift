import Foundation
import JoinCore

enum CalendarAuthorization: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case writeOnly
}

struct CalendarInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let sourceTitle: String
    let color: RGBA
}

/// The calendar backend. EventKit today; a direct Google Calendar implementation could slot in later.
@MainActor
protocol CalendarService: AnyObject {
    var authorization: CalendarAuthorization { get }
    var onChange: (@MainActor () -> Void)? { get set }
    func requestAccess() async -> Bool
    func calendars() -> [CalendarInfo]
    /// `calendarIDs == nil` means every calendar.
    func meetings(from start: Date, to end: Date, calendarIDs: Set<String>?) -> [Meeting]
}
