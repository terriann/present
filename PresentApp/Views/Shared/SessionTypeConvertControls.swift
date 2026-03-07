import SwiftUI
import PresentCore

/// Inline conversion controls shown when the session type chevron is expanded.
///
/// Displays available target types, duration/rhythm options, and a confirmation button.
/// Used in both the menu bar and dashboard active timer panels.
struct SessionTypeConvertControls: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    let session: Session
    /// Callback to dismiss the convert picker after conversion.
    var onConvert: () -> Void

    @State private var targetType: SessionType = .work
    @State private var timeboundMinutes: Int = 25
    @State private var rhythmOption: RhythmOption?

    var body: some View {
        let targets = SessionType.allCases.filter { $0 != session.sessionType }

        VStack(spacing: Constants.spacingCompact) {
            // Target type picker (only when there are multiple targets)
            if targets.count > 1 {
                HStack(spacing: Constants.spacingTight) {
                    ForEach(targets, id: \.self) { type in
                        let isSelected = targetType == type
                        Button {
                            targetType = type
                        } label: {
                            Text(SessionTypeConfig.config(for: type).displayName)
                                .font(.caption2.weight(isSelected ? .semibold : .regular))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(isSelected ? theme.accent.opacity(0.12) : Color.secondary.opacity(0.08), in: Capsule())
                                .foregroundStyle(isSelected ? theme.accent : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Controls for selected target type
            switch targetType {
            case .work:
                Button("Convert to Work Session") {
                    onConvert()
                    Task { await appState.convertSession(ConvertSessionInput(targetType: .work)) }
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)

            case .timebound:
                HStack(spacing: Constants.spacingTight) {
                    TimeboundDurationField(minutes: $timeboundMinutes, size: .compact)
                    Button("Convert to Timebound") {
                        onConvert()
                        Task {
                            await appState.convertSession(
                                ConvertSessionInput(targetType: .timebound, timerMinutes: timeboundMinutes)
                            )
                        }
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.accent)
                }

            case .rhythm:
                HStack(spacing: Constants.spacingTight) {
                    ForEach(Array(appState.rhythmDurationOptions.prefix(4)), id: \.self) { option in
                        let isSelected = rhythmOption == option
                        Button {
                            rhythmOption = option
                        } label: {
                            Text(option.displayLabel)
                                .font(.caption2.weight(isSelected ? .semibold : .regular))
                                .padding(.horizontal, Constants.spacingCompact)
                                .padding(.vertical, 3)
                                .background(isSelected ? theme.accent.opacity(0.12) : Color.secondary.opacity(0.08), in: Capsule())
                                .foregroundStyle(isSelected ? theme.accent : .secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Convert") {
                        guard let option = rhythmOption else { return }
                        onConvert()
                        Task {
                            await appState.convertSession(
                                ConvertSessionInput(
                                    targetType: .rhythm,
                                    timerMinutes: option.focusMinutes,
                                    breakMinutes: option.breakMinutes
                                )
                            )
                        }
                    }
                    .font(.caption2.weight(.medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(rhythmOption == nil ? .secondary : theme.accent)
                    .disabled(rhythmOption == nil)
                }
            }
        }
        .task {
            targetType = SessionType.allCases.first { $0 != session.sessionType } ?? .work
            timeboundMinutes = (try? await appState.getPreference(key: PreferenceKey.defaultTimeboundMinutes)).flatMap(Int.init) ?? Constants.defaultTimeboundMinutes
            rhythmOption = appState.rhythmDurationOptions.first
        }
    }

}

// MARK: - Session Type Convert Label

/// The session type label with an edit icon for convertible sessions.
/// The edit icon appears on hover; an X shows when the picker is open.
/// System activities show a faded, non-interactive label.
struct SessionTypeConvertLabel: View {
    let session: Session
    let isSystemActivity: Bool
    @Binding var showConvertPicker: Bool

    @State private var isHovered = false

    private var showIcon: Bool {
        isHovered || showConvertPicker
    }

    var body: some View {
        if isSystemActivity {
            Text(SessionTypeConfig.config(for: session.sessionType).displayName)
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.35))
        } else {
            Button {
                withAdaptiveAnimation(.easeInOut(duration: 0.15)) {
                    showConvertPicker.toggle()
                }
            } label: {
                Text(SessionTypeConfig.config(for: session.sessionType).displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .overlay(alignment: .trailing) {
                        Image(systemName: showConvertPicker ? "xmark.circle.fill" : "square.and.pencil")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .contentTransition(.symbolEffect(.replace))
                            .opacity(showIcon ? 1 : 0)
                            .offset(x: 14)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in isHovered = hovering }
        }
    }
}
