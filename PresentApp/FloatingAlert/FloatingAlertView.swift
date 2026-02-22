import SwiftUI
import PresentCore

struct FloatingAlertView: View {
    let context: TimerCompletionContext
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(spacing: 16) {
            header
            Divider()
            actions
        }
        .padding(20)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: headerIcon)
                .font(.title)
                .foregroundStyle(theme.accent)

            Text(headerTitle)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(context.durationFormatted)
                .font(.timerDisplay)
                .foregroundStyle(.secondary)

            Text(sessionBadge)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        }
    }

    private var headerIcon: String {
        switch context.completionType {
        case .timeboundExpiry:
            return "timer"
        case .rhythmFocusExpiry:
            return "brain.head.profile"
        case .rhythmBreakExpiry:
            return "cup.and.saucer"
        }
    }

    private var headerTitle: String {
        switch context.completionType {
        case .timeboundExpiry:
            return "\(context.activityTitle) Complete"
        case .rhythmFocusExpiry:
            return "Focus Session Complete"
        case .rhythmBreakExpiry:
            return "Break Complete"
        }
    }

    private var sessionBadge: String {
        switch context.completionType {
        case .timeboundExpiry:
            return "Timebound \(context.timerMinutes)m"
        case .rhythmFocusExpiry(let breakMins, let isLong):
            return isLong ? "Rhythm (Long Break: \(breakMins)m)" : "Rhythm (Break: \(breakMins)m)"
        case .rhythmBreakExpiry:
            return "Break"
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        switch context.completionType {
        case .timeboundExpiry:
            timeboundActions
        case .rhythmFocusExpiry:
            rhythmFocusActions
        case .rhythmBreakExpiry:
            rhythmBreakActions
        }
    }

    private var timeboundActions: some View {
        HStack(spacing: 12) {
            Button {
                appState.dismissTimerAlert()
            } label: {
                Label("Dismiss", systemImage: "xmark")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.bordered)

            Button {
                Task { await appState.restartTimeboundSession() }
            } label: {
                Label("Restart", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
    }

    private var rhythmFocusActions: some View {
        VStack(spacing: 8) {
            if case .rhythmFocusExpiry(let breakMins, _) = context.completionType {
                Button {
                    Task { await appState.startBreakSession() }
                } label: {
                    Label("Start \(breakMins)m Break", systemImage: "cup.and.saucer")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }

            Button {
                Task { await appState.startNextFocusSession() }
            } label: {
                Label("Skip Break", systemImage: "forward")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
        }
    }

    private var rhythmBreakActions: some View {
        VStack(spacing: 8) {
            if case .rhythmBreakExpiry(_, let prevTitle, _, _) = context.completionType {
                Button {
                    Task { await appState.startNextFocusSession() }
                } label: {
                    Label("Resume \(prevTitle)", systemImage: "play")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }

            Button {
                appState.endBreakSession()
            } label: {
                Label("End", systemImage: "stop")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
        }
    }
}
