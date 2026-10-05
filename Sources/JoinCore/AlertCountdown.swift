import Foundation

/// The wording on the full-screen alert: the countdown above the title, the Join label and the
/// snooze choices.
public enum AlertCountdown {
    public enum Phase: Hashable, Sendable {
        case before
        /// The first minute after the start.
        case starting
        case started
        case ended
    }

    public static func phase(start: Date, end: Date, now: Date) -> Phase {
        if now < start { return .before }
        if now >= end { return .ended }
        return now.timeIntervalSince(start) < 60 ? .starting : .started
    }

    /// "Starts in 2:59", "Starts in 1:05:00", "Starting now", "Started 3 min ago", "Ended".
    public static func text(start: Date, end: Date, now: Date) -> String {
        switch phase(start: start, end: end, now: now) {
        case .before:
            // Rounded up, so the clock never reads 0:00 before the start.
            let total = Int(start.timeIntervalSince(now).rounded(.up))
            let hours = total / 3600
            let minutes = total / 60 % 60
            let seconds = total % 60
            if hours > 0 { return String(format: "Starts in %d:%02d:%02d", hours, minutes, seconds) }
            return String(format: "Starts in %d:%02d", minutes, seconds)
        case .starting:
            return "Starting now"
        case .started:
            return "Started \(minutesText(now.timeIntervalSince(start))) ago"
        case .ended:
            return "Ended"
        }
    }

    public static func joinTitle(for phase: Phase) -> String {
        phase == .before ? "Join" : "Join now"
    }

    /// "1 min", "5 min", "1 hr": worded as in Settings.
    public static func snoozeLabel(_ duration: TimeInterval) -> String {
        SettingsOptions.shortDurationTitle(minutes: wholeMinutes(duration))
    }

    /// "Snooze 1 minute", "Snooze 5 minutes", "Snooze 1 hour".
    public static func snoozeAccessibilityLabel(_ duration: TimeInterval) -> String {
        "Snooze \(SettingsOptions.durationTitle(minutes: wholeMinutes(duration)))"
    }

    /// The button that snoozes until the meeting starts; Settings' "The alert offers" chips use it too.
    public static let snoozeUntilStartLabel = "At event start"

    /// VoiceOver keeps the time the button itself leaves out.
    public static func snoozeUntilStartAccessibilityLabel(_ start: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        "Snooze until the event starts at \(MeetingTimeFormatter.shortTime(start, locale: locale, timeZone: timeZone))"
    }

    private static func wholeMinutes(_ duration: TimeInterval) -> Int {
        max(1, Int((duration / 60).rounded()))
    }

    /// "3 min", "1 hr", "1 hr 5 min"; whole minutes, rounded down.
    private static func minutesText(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int(seconds / 60))
        if minutes < 60 { return "\(minutes) min" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(rest) min"
    }
}
