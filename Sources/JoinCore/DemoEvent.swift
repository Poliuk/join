import Foundation

/// The sample event of Test Full-Screen Alert and Test Notification: "Hello, I’m a demo event", starting 3
/// minutes from now, an hour long, on the Work calendar in Conference Room A, with a meeting link. What each
/// says to set it apart from a real one says "test", like the buttons.
public enum DemoEvent {
    /// Its meeting id. Never an EventKit occurrence's, which always has an "@".
    public static let id = "demo"
    public static let calendarTitle = "Work"
    public static let calendarColor = RGBA(rgb: 0x1A9FC0)
    public static let location = "Conference Room A"
    public static let joinURL = URL(string: "https://meet.google.com/abc-defg-hij")
    static let startsIn: TimeInterval = 3 * 60
    static let duration: TimeInterval = 60 * 60

    /// Under the test full-screen alert's Dismiss: what it is, and how to close it.
    public static let fullScreenAlertNote = "This is a test full-screen alert. Press Esc to close it."
    /// The test notification card's third line, where a meeting's card has its location.
    public static let notificationNote = "This is a test notification."

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
