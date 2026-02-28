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
    @State private var includeElapsed = false

    var body: some View {
        let targets = SessionType.allCases.filter { $0 != session.sessionType }

        VStack(spacing: Constants.spacingCompact) {
            // Target type picker (only when there are multiple targets)
            if targets.count > 1 {
                HStack(spacing: 4) {
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
                HStack(spacing: 4) {
                    TextField("", value: $timeboundMinutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 48)
                        .font(.caption)
                    Text("min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
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

                    if let option = rhythmOption {
                        Toggle(isOn: $includeElapsed) {
                            Text("Include elapsed \(effectiveElapsedMinutes(focusMinutes: option.focusMinutes))m in first segment")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .toggleStyle(.checkbox)
                    }

                    Button("Convert to Rhythm") {
                        guard let option = rhythmOption else { return }
                        onConvert()
                        Task {
                            await appState.convertSession(
                                ConvertSessionInput(
                                    targetType: .rhythm,
                                    timerMinutes: option.focusMinutes,
                                    breakMinutes: option.breakMinutes,
                                    includeElapsed: includeElapsed
                                )
                            )
                        }
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(rhythmOption == nil ? .secondary : theme.accent)
                    .disabled(rhythmOption == nil)
                }
            }
        }
        .task {
            targetType = SessionType.allCases.first { $0 != session.sessionType } ?? .work
            timeboundMinutes = (try? await appState.service.getPreference(key: PreferenceKey.defaultTimeboundMinutes)).flatMap(Int.init) ?? Constants.defaultTimeboundMinutes
            rhythmOption = appState.rhythmDurationOptions.first
        }
    }

    // MARK: - Helpers

    /// Effective elapsed minutes for the "Include elapsed" checkbox.
    /// If elapsed > focus duration, uses `elapsed % focus` to show the partial segment.
    private func effectiveElapsedMinutes(focusMinutes: Int) -> Int {
        let elapsed = appState.timerElapsedSeconds
        let focusSeconds = focusMinutes * 60
        let effective = focusSeconds > 0 ? elapsed % focusSeconds : elapsed
        return max(1, effective / 60)
    }
}

// MARK: - Session Type Convert Label

/// The session type label with a chevron for convertible sessions.
/// System activities show a faded, non-interactive label.
struct SessionTypeConvertLabel: View {
    let session: Session
    let isSystemActivity: Bool
    @Binding var showConvertPicker: Bool

    var body: some View {
        if isSystemActivity {
            HStack(spacing: 2) {
                Text(SessionTypeConfig.config(for: session.sessionType).displayName)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .font(.caption)
            .foregroundStyle(.secondary.opacity(0.35))
        } else {
            Button {
                withAdaptiveAnimation(.easeInOut(duration: 0.15)) {
                    showConvertPicker.toggle()
                }
            } label: {
                HStack(spacing: 2) {
                    Text(SessionTypeConfig.config(for: session.sessionType).displayName)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}
