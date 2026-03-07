import SwiftUI
import PresentCore

struct SessionControls: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    private var showCancelButton: Bool {
        appState.timerElapsedSeconds <= Constants.cancelWindowSeconds
    }

    var body: some View {
        HStack(spacing: Constants.spacingToolbar) {
            if let session = appState.currentSession {
                switch session.state {
                case .running:
                    Button {
                        Task { await appState.pauseSession() }
                    } label: {
                        Image(systemName: "pause.circle.fill")
                            .font(.controlIcon)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(SessionControlButtonStyle())
                    .accessibilityLabel("Pause session")
                    .help("Pause session")

                case .paused:
                    Button {
                        Task { await appState.resumeSession() }
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.controlIcon)
                            .foregroundStyle(theme.primary)
                    }
                    .buttonStyle(SessionControlButtonStyle(hoverColor: theme.primary))
                    .accessibilityLabel("Resume session")
                    .help("Resume session")

                default:
                    EmptyView()
                }

                Button {
                    Task { await appState.stopSession() }
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.controlIcon)
                        .foregroundStyle(theme.alert)
                }
                .buttonStyle(SessionControlButtonStyle(hoverColor: theme.alert, restingOpacity: 0.5))
                .accessibilityLabel("Stop session")
                .help("Stop session")

                if showCancelButton {
                    Button {
                        Task { await appState.cancelSession() }
                    } label: {
                        Image(systemName: "trash")
                            .font(.controlIconSmall)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(SessionControlButtonStyle())
                    .accessibilityLabel("Discard session")
                    .help("Discard session")
                    .transition(.opacity)
                }
            }
        }
        .adaptiveAnimation(.easeOut(duration: 2), reduced: .linear(duration: 0.6), value: showCancelButton)
    }
}
