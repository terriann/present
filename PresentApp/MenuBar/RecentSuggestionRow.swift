import SwiftUI
import PresentCore

struct RecentSuggestionRow: View {
    @Environment(ThemeManager.self) private var theme

    let activity: Activity
    let session: Session
    let onStart: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onStart) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.callout)
                    .foregroundStyle(theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(theme.accent)
                        .lineLimit(1)

                    Text(sessionDescription)
                        .font(.caption)
                        .foregroundStyle(theme.accent.opacity(0.7))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundStyle(isHovered ? theme.accent : theme.accent.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(theme.accent.opacity(isHovered ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var sessionDescription: String {
        let typeName = SessionTypeConfig.config(for: session.sessionType).displayName
        var parts = [typeName]

        if let duration = session.durationSeconds {
            parts.append(TimeFormatting.formatDuration(seconds: duration))
        } else if let minutes = session.timerLengthMinutes {
            parts.append("\(minutes) min")
        }

        if let endedAt = session.endedAt {
            parts.append(Self.relativeTime(since: endedAt))
        }

        return parts.joined(separator: " \u{00B7} ")
    }

    private static func relativeTime(since date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m ago"
        } else {
            let hours = seconds / 3600
            let remaining = (seconds % 3600) / 60
            if remaining == 0 {
                return "\(hours)h ago"
            }
            return "\(hours)h \(remaining)m ago"
        }
    }
}
