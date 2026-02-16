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
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(activity.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)

                    Text(sessionDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "play.fill")
                    .font(.caption2)
                    .foregroundStyle(isHovered ? theme.accent : .secondary)
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
        if let minutes = session.timerLengthMinutes {
            return "\(typeName) \u{00B7} \(minutes) min"
        }
        return typeName
    }
}
