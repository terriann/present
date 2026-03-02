import SwiftUI
import PresentCore

struct SessionRow: View {
    @Environment(ThemeManager.self) private var theme

    let session: Session
    let activityTitle: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(activityTitle)
                    .font(.body.bold())

                HStack(spacing: 8) {
                    Text(SessionTypeConfig.config(for: session.sessionType).displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(TimeFormatting.formatTime(session.startedAt))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            TicketBadge(ticketId: session.ticketId, link: session.link)
            noteIndicator

            Spacer()

            if let duration = session.durationSeconds {
                Text(TimeFormatting.formatDuration(seconds: duration))
                    .font(.durationValue)
                    .foregroundStyle(.secondary)
            }

            stateIndicator
        }
        .padding(.vertical, 2)
    }

    // MARK: - Metadata Indicators

    @ViewBuilder
    private var noteIndicator: some View {
        if let note = session.note {
            Image(systemName: "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Has note")
                .help(note)
        }
    }

    // MARK: - State Indicator

    private var stateIndicator: some View {
        Group {
            switch session.state {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.success)
            case .cancelled:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            case .running:
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(theme.accent)
            case .paused:
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(theme.warning)
            }
        }
        .font(.body)
    }
}
