import Foundation

/// Human-readable times for the alert, the menu bar, and list rows.
/// Locale-sensitive output takes the locale/time zone as parameters so it can be tested.
public enum MeetingTimeFormatter {
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

    public static func truncate(_ text: String, to maxLength: Int) -> String {
        guard text.count > maxLength, maxLength > 1 else { return text }
        return String(text.prefix(maxLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
