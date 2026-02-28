import SwiftUI
import PresentCore

/// Sheet for converting an active session to a different type.
///
/// Adapts its controls based on the available target types:
/// - **Timebound**: duration field
/// - **Rhythm**: rhythm option pills + include-elapsed checkbox
/// - **Work**: immediate conversion (no extra options)
struct ConvertSessionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss

    let session: Session

    @State private var targetType: SessionType = .work
    @State private var timeboundMinutes: Int = 25
    @State private var rhythmOption: RhythmOption?
    @State private var includeElapsed = false

    private var targets: [SessionType] {
        SessionType.allCases.filter { $0 != session.sessionType }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.spacingPage) {
            Text("Convert Session")
                .font(.headline)

            Text("Time already tracked is preserved.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Target type picker
            if targets.count > 1 {
                HStack(spacing: Constants.spacingCompact) {
                    ForEach(targets, id: \.self) { type in
                        let isSelected = targetType == type
                        Button {
                            targetType = type
                        } label: {
                            Text(SessionTypeConfig.config(for: type).displayName)
                                .font(.callout.weight(isSelected ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(isSelected ? theme.accent.opacity(0.15) : Color.secondary.opacity(0.08), in: Capsule())
                                .foregroundStyle(isSelected ? theme.accent : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Target-specific controls
            switch targetType {
            case .timebound:
                HStack(spacing: Constants.spacingCompact) {
                    Text("Duration:")
                        .font(.body)
                    TextField("", value: $timeboundMinutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                    Text("minutes")
                        .foregroundStyle(.secondary)
                }

            case .rhythm:
                VStack(alignment: .leading, spacing: Constants.spacingCompact) {
                    HStack(spacing: Constants.spacingCompact) {
                        ForEach(Array(appState.rhythmDurationOptions.prefix(4)), id: \.self) { option in
                            let isSelected = rhythmOption == option
                            Button {
                                rhythmOption = option
                            } label: {
                                Text(option.displayLabel)
                                    .font(.callout.weight(isSelected ? .semibold : .regular))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(isSelected ? theme.accent.opacity(0.12) : Color.secondary.opacity(0.08), in: Capsule())
                                    .foregroundStyle(isSelected ? theme.accent : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let option = rhythmOption {
                        Toggle(isOn: $includeElapsed) {
                            Text("Include elapsed \(effectiveElapsedMinutes(focusMinutes: option.focusMinutes))m in first segment")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .toggleStyle(.checkbox)
                    }
                }

            case .work:
                EmptyView()
            }

            // Actions
            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(convertButtonLabel) {
                    performConversion()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isConvertEnabled)
            }
        }
        .padding(Constants.spacingPage)
        .frame(minWidth: 340)
        .task {
            targetType = targets.first ?? .work
            timeboundMinutes = (try? await appState.service.getPreference(key: PreferenceKey.defaultTimeboundMinutes)).flatMap(Int.init) ?? Constants.defaultTimeboundMinutes
            rhythmOption = appState.rhythmDurationOptions.first
        }
    }

    // MARK: - Helpers

    private var convertButtonLabel: String {
        "Convert to \(SessionTypeConfig.config(for: targetType).displayName)"
    }

    private var isConvertEnabled: Bool {
        switch targetType {
        case .timebound: timeboundMinutes >= 1
        case .rhythm: rhythmOption != nil
        case .work: true
        }
    }

    private func performConversion() {
        dismiss()
        Task {
            switch targetType {
            case .timebound:
                await appState.convertSession(
                    ConvertSessionInput(targetType: .timebound, timerMinutes: timeboundMinutes)
                )
            case .rhythm:
                guard let option = rhythmOption else { return }
                await appState.convertSession(
                    ConvertSessionInput(
                        targetType: .rhythm,
                        timerMinutes: option.focusMinutes,
                        breakMinutes: option.breakMinutes,
                        includeElapsed: includeElapsed
                    )
                )
            case .work:
                await appState.convertSession(ConvertSessionInput(targetType: .work))
            }
        }
    }

    private func effectiveElapsedMinutes(focusMinutes: Int) -> Int {
        let elapsed = appState.timerElapsedSeconds
        let focusSeconds = focusMinutes * 60
        let effective = focusSeconds > 0 ? elapsed % focusSeconds : elapsed
        return max(1, effective / 60)
    }
}
