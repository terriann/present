import SwiftUI
import PresentCore

struct SessionControls: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 16) {
            if let session = appState.currentSession {
                switch session.state {
                case .running:
                    Button {
                        Task { await appState.pauseSession() }
                    } label: {
                        Image(systemName: "pause.circle.fill")
                            .font(.title)
                    }
                    .buttonStyle(.plain)
                    .help("Pause session")

                case .paused:
                    Button {
                        Task { await appState.resumeSession() }
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.title)
                    }
                    .buttonStyle(.plain)
                    .help("Resume session")

                default:
                    EmptyView()
                }

                Button {
                    Task { await appState.stopSession() }
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title)
                        .foregroundStyle(theme.alert)
                }
                .buttonStyle(.plain)
                .help("Stop session")

                if appState.timerElapsedSeconds <= 10 {
                    Button {
                        Task { await appState.cancelSession() }
                    } label: {
                        Image(systemName: "trash")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Discard session")
                }
            }
        }
    }
}
