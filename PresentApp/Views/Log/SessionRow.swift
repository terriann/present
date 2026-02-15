import SwiftUI
import PresentCore

struct SessionRow: View {
    let session: Session
    let activityTitle: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(activityTitle)
                    .font(.body.bold())

                HStack(spacing: 8) {
                    Text(SessionTypeConfig.config(for: session.sessionType).displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(TimeFormatting.formatTime(session.startedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let duration = session.durationSeconds {
                Text(TimeFormatting.formatDuration(seconds: duration))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            stateIndicator
        }
        .padding(.vertical, 2)
    }

    private var stateIndicator: some View {
        Group {
            switch session.state {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .cancelled:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            case .running:
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(.blue)
            case .paused:
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.body)
    }
}
