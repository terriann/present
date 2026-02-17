import Foundation

public enum TimeFormatting {
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

    /// Format a date for display (e.g., "Today", "Yesterday", or "Feb 14, 2026")
    public static func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
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
