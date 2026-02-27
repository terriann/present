import SwiftUI
import PresentCore

struct SessionRow: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.openURL) private var openURL

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

            ticketBadge

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

    // MARK: - Ticket Badge

    @ViewBuilder
    private var ticketBadge: some View {
        if let ticketId = session.ticketId, let link = session.link, let url = URL(string: link) {
            Button {
                openURL(url)
            } label: {
                Text(ticketId)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.accent.opacity(0.12), in: Capsule())
                    .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
            .help(link)
        } else if let link = session.link, let url = URL(string: link) {
            Button {
                openURL(url)
            } label: {
                Text(url.host ?? link)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.accent.opacity(0.12), in: Capsule())
                    .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
            .help(link)
        } else if session.note != nil {
            Image(systemName: "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)
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
