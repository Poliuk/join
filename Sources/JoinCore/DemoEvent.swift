import Foundation

/// The sample event of Show Demo's full-screen alert and of Send Demo Notification: "Hello, I’m a demo event",
/// starting 3 minutes from now, an hour long, on the Work calendar in Conference Room A, with a meeting link.
public enum DemoEvent {
    /// Its meeting id. Never an EventKit occurrence's, which always has an "@".
    public static let id = "demo"
    public static let calendarTitle = "Work"
    public static let calendarColor = RGBA(rgb: 0x1A9FC0)
    public static let location = "Conference Room A"
    public static let joinURL = URL(string: "https://meet.google.com/abc-defg-hij")
    static let startsIn: TimeInterval = 3 * 60
    static let duration: TimeInterval = 60 * 60

    /// The demo event as of `now`. It starts on a whole second, like a real event, so the full-screen alert's
    /// countdown starts at 3:00 and steps evenly.
    public static func meeting(now: Date) -> Meeting {
        let start = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate + startsIn).rounded(.down))
        return Meeting(
            id: id,
            title: MenuBarPresenter.demoEventTitle,
            start: start,
            end: start.addingTimeInterval(duration),
            calendarTitle: calendarTitle,
            calendarColor: calendarColor,
            location: location,
            joinURL: joinURL
        )
    }
}
