import SwiftUI
import PresentCore

struct SessionControls: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var showCancelButton = true

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
                    .accessibilityLabel("Pause session")
                    .help("Pause session")

                case .paused:
                    Button {
                        Task { await appState.resumeSession() }
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.title)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Resume session")
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
                .accessibilityLabel("Stop session")
                .help("Stop session")

                if showCancelButton {
                    Button {
                        Task { await appState.cancelSession() }
                    } label: {
                        Image(systemName: "trash")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Discard session")
                    .help("Discard session")
                    .allowsHitTesting(appState.timerElapsedSeconds <= 10)
                    .transition(.opacity)
                }
            }
        }
        .adaptiveAnimation(.easeOut(duration: 2), reduced: .linear(duration: 0.6), value: showCancelButton)
        .onChange(of: appState.timerElapsedSeconds) { _, newValue in
            if newValue > 10 && showCancelButton {
                withAdaptiveAnimation(.easeOut(duration: 2), reduced: .linear(duration: 0.6)) {
                    showCancelButton = false
                }
            }
        }
        .onChange(of: appState.currentSession?.id) { _, _ in
            showCancelButton = true
        }
    }
}
