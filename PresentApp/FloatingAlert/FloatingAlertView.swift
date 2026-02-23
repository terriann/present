import SwiftUI
import PresentCore

// MARK: - Constants

/// Shared hover transition for all floating alert buttons and cards.
private let alertHoverAnimation: Animation = .easeInOut(duration: 0.3)

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
            } else if context.completionType.isFocusExpiry {
                FocusBrainIcon()
            } else {
                Image(systemName: headerIcon)
                    .font(.title)
                    .foregroundStyle(.tertiary)
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
            } else if context.completionType.isTimeboundBreakExpiry {
                HStack(spacing: 0) {
                    Text("\(context.timerMinutes)m")
                        .font(.timerDisplay)
                        .foregroundStyle(.secondary)
                    Text(" / \(context.timerMinutes)m")
                        .font(.timerDisplay)
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            } else if context.completionType.isFocusExpiry {
                HStack(spacing: 0) {
                    Text("\(context.timerMinutes)m")
                        .font(.timerDisplay)
                        .foregroundStyle(.secondary)
                    Text(" / \(context.timerMinutes)m")
                        .font(.timerDisplay)
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            } else {
                HStack(spacing: 0) {
                    Text("\(context.timerMinutes)m")
                        .font(.timerDisplay)
                        .foregroundStyle(.secondary)
                    Text(" / \(context.timerMinutes)m")
                        .font(.timerDisplay)
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
        }
    }

    private var headerIcon: String {
        switch context.completionType {
        case .timeboundExpiry:
            return "timer"
        case .rhythmFocusExpiry:
            return "brain.head.profile"
        case .rhythmBreakExpiry, .timeboundBreakExpiry:
            return "cup.and.saucer"
        }
    }

    private var headerTitle: String {
        switch context.completionType {
        case .timeboundExpiry:
            return "\(context.activityTitle) Complete"
        case .rhythmFocusExpiry:
            return "Focus Session Complete"
        case .rhythmBreakExpiry, .timeboundBreakExpiry:
            return "Break Complete"
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
        case .timeboundBreakExpiry:
            timeboundBreakActions
        }
    }

    private var timeboundActions: some View {
        VStack(spacing: Constants.spacingCard) {
            ResumeActivityCard(
                title: "Continue \(context.activityTitle)",
                subtitle: "Timebound \u{00B7} \(context.timerMinutes)m",
                theme: theme
            ) {
                Task { await appState.restartTimeboundSession() }
            }

            DismissButton(theme: theme) {
                appState.dismissTimerAlert()
            }
        }
    }

    private var rhythmFocusActions: some View {
        VStack(spacing: Constants.spacingCard) {
            if case .rhythmFocusExpiry(let breakMins, _) = context.completionType {
                ResumeActivityCard(
                    title: "Start \(breakMins)m Break",
                    icon: "play.fill",
                    iconEffect: .replace(hover: "cup.and.saucer.fill"),
                    theme: theme
                ) {
                    Task { await appState.startBreakSession() }
                }

                ResumeActivityCard(
                    title: "No break this time \u{00B7} \(context.activityTitle)",
                    subtitle: "Rhythm Session \u{00B7} \(context.timerMinutes)m / \(breakMins)m",
                    icon: "forward.fill",
                    iconEffect: .replace(hover: "brain.filled.head.profile", flipHover: true),
                    muted: true,
                    theme: theme
                ) {
                    Task { await appState.startNextFocusSession() }
                }
            }

            DismissButton(label: "End Rhythm Session", theme: theme) {
                appState.dismissTimerAlert()
            }
        }
    }

    private var rhythmBreakActions: some View {
        VStack(spacing: Constants.spacingCard) {
            if case .rhythmBreakExpiry(_, let prevTitle, let prevTimer, let prevBreak) = context.completionType {
                resumeCard(title: "Resume \(prevTitle)", timerMinutes: prevTimer, breakMinutes: prevBreak)
            }

            DismissButton(theme: theme) {
                appState.endBreakSession()
            }
        }
    }

    private var timeboundBreakActions: some View {
        VStack(spacing: Constants.spacingCard) {
            if case .timeboundBreakExpiry(let recentId, let recentTitle, let recentTimer, let recentType) = context.completionType,
               let recentId, let recentTitle {
                let subtitle = timeboundBreakResumeSubtitle(type: recentType, minutes: recentTimer)
                ResumeActivityCard(
                    title: "Resume \(recentTitle)",
                    subtitle: subtitle,
                    theme: theme
                ) {
                    Task { await appState.startNextFocusSession() }
                }
            }

            DismissButton(theme: theme) {
                appState.endBreakSession()
            }
        }
    }

    private func timeboundBreakResumeSubtitle(type: SessionType?, minutes: Int?) -> String {
        let typeName = switch type {
        case .rhythm: "Rhythm"
        case .timebound: "Timebound"
        case .work, .none: "Work"
        }
        if let minutes {
            return "\(typeName) \u{00B7} \(minutes)m"
        }
        return typeName
    }

    // MARK: - Resume Card

    private func resumeCard(title: String, timerMinutes: Int, breakMinutes: Int) -> some View {
        ResumeActivityCard(
            title: title,
            subtitle: "Rhythm Session \u{00B7} \(timerMinutes)m / \(breakMinutes)m",
            theme: theme
        ) {
            Task { await appState.startNextFocusSession() }
        }
    }
}

// MARK: - Focus Brain Icon

/// Flipped brain.filled.head.profile at tertiary opacity,
/// matching SteamingCupIcon's visual weight.
private struct FocusBrainIcon: View {
    var body: some View {
        Image(systemName: "brain.filled.head.profile")
            .font(.title)
            .foregroundStyle(.tertiary)
            .scaleEffect(x: -1, y: 1)
    }
}

// MARK: - Resume Activity Card

/// Icon hover effect for ResumeActivityCard.
enum IconHoverEffect {
    /// Swap to a different symbol with a replace transition (default).
    /// Set `flipHover` to mirror the hover icon horizontally.
    case replace(hover: String, flipHover: Bool = false)
    /// Nudge the icon rightward — reinforces "skip ahead" / forward motion.
    case nudge
    /// Gentle lift with slight scale — suggests settling in, starting something calm.
    case lift
}

/// Card-style action button for floating alerts.
/// Primary style: theme.primary background. Muted style: grey default,
/// theme.primary on hover (for secondary actions the user might skip).
struct ResumeActivityCard: View {
    let title: String
    var subtitle: String?
    var icon: String = "arrow.counterclockwise"
    var iconEffect: IconHoverEffect = .replace(hover: "play.fill")
    var muted: Bool = false
    let theme: ThemeManager
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Constants.spacingCompact) {
                iconView

                if let subtitle {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                } else {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(Constants.spacingCard)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(cardFill)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAdaptiveAnimation(alertHoverAnimation) {
                isHovered = hovering
            }
        }
    }

    // MARK: Icon

    @ViewBuilder
    private var iconView: some View {
        switch iconEffect {
        case .replace(let hoverIcon, let flipHover):
            Image(systemName: isHovered ? hoverIcon : icon)
                .font(.callout)
                .foregroundStyle(.white)
                .scaleEffect(x: (isHovered && flipHover) ? -1 : 1, y: 1)
                .frame(width: 16, alignment: .center)
                .contentTransition(.symbolEffect(.replace))
        case .nudge:
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(.white)
                .frame(width: 16, alignment: .center)
                .offset(x: isHovered ? 3 : 0)
        case .lift:
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(.white)
                .frame(width: 16, alignment: .center)
                .scaleEffect(isHovered ? 1.15 : 1.0)
                .offset(y: isHovered ? -2 : 0)
        }
    }

    private var cardFill: some ShapeStyle {
        if muted {
            return AnyShapeStyle(isHovered ? theme.primary.opacity(0.45) : Color.secondary.opacity(0.3))
        }
        return AnyShapeStyle(theme.primary.opacity(isHovered ? 0.65 : 0.45))
    }
}

// MARK: - End Rhythm Button

/// Secondary dismiss button. Grey default with white text; hover reveals alert
/// color on background and icon.
struct DismissButton: View {
    var label: String = "Done for now"
    var icon: String = "stop.fill"
    var hoverIcon: String = "moon.zzz.fill"
    let theme: ThemeManager
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: isHovered ? hoverIcon : icon)
                    .font(.caption)
                    .foregroundStyle(isHovered ? theme.alert : .white)
                    .contentTransition(.symbolEffect(.replace))
                Text(label)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? theme.alert.opacity(0.2) : Color.secondary.opacity(0.3))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAdaptiveAnimation(alertHoverAnimation) {
                isHovered = hovering
            }
        }
    }
}
