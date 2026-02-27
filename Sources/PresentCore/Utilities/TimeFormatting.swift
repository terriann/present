import Foundation

public enum TimeFormatting {
    /// Round seconds down to the nearest whole minute (e.g., 89 → 60, 150 → 120).
    /// Use this when summing session durations for display — round each session first, then sum,
    /// so the total matches the individual displayed values.
    public static func floorToMinute(_ seconds: Int) -> Int {
        (seconds / 60) * 60
    }

    /// Format seconds as "Xh Ym" (e.g., "2h 15m") or "Xm" for short durations
    public static func formatDuration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Format seconds as "HH:MM:SS" for timer display
    public static func formatTimer(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    /// Format a date for display (e.g., "Today", "Yesterday", or "Feb 14, 2026").
    /// Pass a custom `calendar` to control timezone interpretation (defaults to `.current`).
    public static func formatDate(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }

    /// Format a time for display (e.g., "2:30 PM")
    public static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Format a time with a day label when it falls on a different calendar day than `referenceDate`.
    /// Returns e.g. "11:23 PM" for same-day or "10:08 AM (Saturday)" for a different day.
    /// Pass a custom `calendar` to control timezone interpretation (defaults to `.current`).
    public static func formatTime(_ date: Date, referenceDate: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let time = formatter.string(from: date)

        if !calendar.isDate(date, inSameDayAs: referenceDate) {
            let dayFormatter = DateFormatter()
            dayFormatter.calendar = calendar
            dayFormatter.timeZone = calendar.timeZone
            dayFormatter.dateFormat = "EEEE"
            return "\(time) (\(dayFormatter.string(from: date)))"
        }
        return time
    }

    /// Format a week date range (e.g., "February 17 – February 23, 2026" or "December 30, 2025 – January 5, 2026").
    /// Pass a custom `calendar` to control timezone interpretation (defaults to `.current`).
    public static func formatWeekRange(start: Date, end: Date, calendar: Calendar = .current) -> String {
        let startFormatter = DateFormatter()
        let endFormatter = DateFormatter()
        startFormatter.calendar = calendar
        startFormatter.timeZone = calendar.timeZone
        endFormatter.calendar = calendar
        endFormatter.timeZone = calendar.timeZone
        if calendar.component(.year, from: start) == calendar.component(.year, from: end) {
            startFormatter.dateFormat = "MMMM d"
            endFormatter.dateFormat = "MMMM d, yyyy"
        } else {
            startFormatter.dateFormat = "MMMM d, yyyy"
            endFormatter.dateFormat = "MMMM d, yyyy"
        }
        return "\(startFormatter.string(from: start)) – \(endFormatter.string(from: end))"
    }

    /// Format a date as relative time + full timestamp (e.g., "2 days ago (2026-02-14 15:30:45)")
    public static func formatRelativeWithTimestamp(_ date: Date) -> String {
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        let relativeString = relative.localizedString(for: date, relativeTo: Date())

        let absolute = DateFormatter()
        absolute.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let absoluteString = absolute.string(from: date)

        return "\(relativeString) (\(absoluteString))"
    }
}
