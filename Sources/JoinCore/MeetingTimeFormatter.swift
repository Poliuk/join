import Foundation

/// Human-readable times for the alert, the menu bar, and list rows.
/// Locale-sensitive output takes the calendar/locale as parameters so it can be tested.
public enum MeetingTimeFormatter {
    /// "<1m", "12m", "1h 5m", "2h", "3d" — for the menu bar and list rows.
    public static func compactDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, seconds.rounded())
        if total < 60 { return "<1m" }
        let minutes = Int(total / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours < 24 { return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m" }
        return "\(hours / 24)d"
    }

    /// "45s", "2m 13s", "1h 05m" — for the live countdown on the alert.
    public static func preciseDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.rounded()))
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        if minutes < 60 { return String(format: "%dm %02ds", minutes, total % 60) }
        return String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }

    public static func countdown(start: Date, end: Date, now: Date) -> String {
        if now < start { return "Starts in \(preciseDuration(start.timeIntervalSince(now)))" }
        if now < end {
            let ago = now.timeIntervalSince(start)
            return ago < 60 ? "Started just now" : "Started \(compactDuration(ago)) ago"
        }
        return "Ended"
    }

    /// "in 12m" before the meeting, "45m left" during it, nil afterwards.
    public static func rowDetail(start: Date, end: Date, now: Date) -> String? {
        if now < start { return "in \(compactDuration(start.timeIntervalSince(now)))" }
        if now < end { return "\(compactDuration(end.timeIntervalSince(now))) left" }
        return nil
    }

    /// "4:00 – 5:00 PM" within a day, "11:30 PM – 12:30 AM" overnight, "Mon 9:00 AM – Wed 5:00 PM"
    /// beyond a day. DateIntervalFormatter alone prints full dates as soon as a range crosses midnight.
    public static func timeRange(start: Date, end: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if calendar.isDate(start, inSameDayAs: end) {
            let formatter = DateIntervalFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter.string(from: start, to: end)
        }
        if end.timeIntervalSince(start) < 24 * 60 * 60 {
            return "\(shortTime(start, locale: locale, timeZone: timeZone)) – \(shortTime(end, locale: locale, timeZone: timeZone))"
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEjmm")
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    public static func shortTime(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// "Today", "Tomorrow", or "Thu 19 Jun" (localized).
    public static func dayHeading(for date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter.string(from: date)
    }


    public static func truncate(_ text: String, to maxLength: Int) -> String {
        guard text.count > maxLength, maxLength > 1 else { return text }
        return String(text.prefix(maxLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
