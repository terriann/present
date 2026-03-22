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
        VStack(spacing: Constants.spacingCompact) {
            // Session type picker — current type shown as non-interactive label
            HStack(spacing: Constants.spacingTight) {
                ForEach(SessionType.allCases, id: \.self) { type in
                    let isCurrent = type == session.sessionType
                    let isSelected = !isCurrent && targetType == type

                    if isCurrent {
                        Text(SessionTypeConfig.config(for: type).displayName)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(theme.accent.opacity(0.15), in: Capsule())
                            .foregroundStyle(theme.accent)
                    } else {
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

            // Duration/option controls for selected target type
            switch targetType {
            case .work:
                EmptyView()

            case .timebound:
                TimeboundDurationField(minutes: $timeboundMinutes, size: .compact)

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
                }
            }

            // Convert button — always on its own row
            convertButton
        }
        .padding(Constants.spacingCompact)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .task {
            targetType = SessionType.allCases.first { $0 != session.sessionType } ?? .work
            timeboundMinutes = await appState.loadDefaultTimeboundMinutes()
            rhythmOption = appState.rhythmDurationOptions.first
        }
    }

    // MARK: - Convert Button

    private var convertButton: some View {
        let label = "Convert to \(SessionTypeConfig.config(for: targetType).displayName)"
        let isDisabled = targetType == .rhythm && rhythmOption == nil

        return Button {
            switch targetType {
            case .work:
                onConvert()
                Task { await appState.convertSession(ConvertSessionInput(targetType: .work)) }
            case .timebound:
                onConvert()
                Task {
                    await appState.convertSession(
                        ConvertSessionInput(targetType: .timebound, timerMinutes: timeboundMinutes)
                    )
                }
            case .rhythm:
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
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    isDisabled ? Color.secondary.opacity(0.08) : theme.accent,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .foregroundStyle(isDisabled ? .secondary : theme.constantWhite)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
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
                HStack(spacing: 4) {
                    Text(SessionTypeConfig.config(for: session.sessionType).displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Image(systemName: showConvertPicker ? "xmark.circle.fill" : "square.and.pencil")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.symbolEffect(.replace))
                        .opacity(showIcon ? 1 : 0)
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
