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
            if context.completionType.isBreakExpiry {
                SteamingCupIcon(size: 28)
                    .foregroundStyle(theme.accent)
            } else {
                Image(systemName: headerIcon)
                    .font(.title)
                    .foregroundStyle(theme.accent)
            }

            Text(headerTitle)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if case .rhythmBreakExpiry(_, _, _, let breakMins) = context.completionType {
                HStack(spacing: 0) {
                    Text("0m")
                        .font(.timerDisplay)
                        .foregroundStyle(.secondary)
                    Text(" / \(breakMins)m")
                        .font(.timerDisplay)
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            } else {
                Text(context.durationFormatted)
                    .font(.timerDisplay)
                    .foregroundStyle(.secondary)
            }

            if !context.completionType.isBreakExpiry {
                Text(sessionBadge)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
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
        VStack(spacing: Constants.spacingCard) {
            if case .rhythmBreakExpiry(_, let prevTitle, let prevTimer, let prevBreak) = context.completionType {
                resumeCard(title: prevTitle, timerMinutes: prevTimer, breakMinutes: prevBreak)
            }

            EndRhythmButton(theme: theme) {
                appState.endBreakSession()
            }
        }
    }

    // MARK: - Resume Card

    private func resumeCard(title: String, timerMinutes: Int, breakMinutes: Int) -> some View {
        ResumeActivityCard(
            title: title,
            subtitle: "Rhythm \u{00B7} \(timerMinutes)m / \(breakMinutes)m break",
            theme: theme
        ) {
            Task { await appState.startNextFocusSession() }
        }
    }
}

// MARK: - Resume Activity Card

/// Card-style button for resuming the previous focus activity after a break.
/// Styled to match QuickStartRow: activity title, session subtitle, hover state.
struct ResumeActivityCard: View {
    let title: String
    let subtitle: String
    let theme: ThemeManager
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Constants.spacingCompact) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isHovered ? theme.accent : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(isHovered ? AnyShapeStyle(theme.accent.opacity(0.6)) : AnyShapeStyle(.tertiary))
            }
            .padding(Constants.spacingCard)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? theme.accent.opacity(0.1) : Color.primary.opacity(0.05))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAdaptiveAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - End Rhythm Button

/// Destructive-style button for ending the rhythm session entirely.
/// Uses alert color with a subtle hover deepening effect.
struct EndRhythmButton: View {
    let theme: ThemeManager
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "stop.fill")
                    .font(.caption)
                Text("Done for now")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(theme.alert)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.alert.opacity(isHovered ? 0.2 : 0.12))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAdaptiveAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}
