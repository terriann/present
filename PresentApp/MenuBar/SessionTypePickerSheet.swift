import SwiftUI
import PresentCore

struct SessionTypePickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let activity: Activity
    @State private var selectedType: SessionType = .work
    @State private var selectedRhythmOption: RhythmOption?
    @State private var timeboundMinutes: Int = 25

    var body: some View {
        VStack(spacing: 16) {
            Text("Start Session")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text(activity.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Session Type", selection: $selectedType) {
                ForEach(SessionType.allCases, id: \.self) { type in
                    Text(SessionTypeConfig.config(for: type).displayName)
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)

            if selectedType == .rhythm {
                Picker("Duration", selection: $selectedRhythmOption) {
                    ForEach(appState.rhythmDurationOptions, id: \.self) { option in
                        Text(option.displayLabel).tag(Optional(option))
                    }
                }
                .pickerStyle(.segmented)
            } else if selectedType == .timebound {
                TimeboundDurationField(minutes: $timeboundMinutes, size: .regular)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Start") {
                    Task {
                        guard let activityId = activity.id else { return }
                        switch selectedType {
                        case .rhythm:
                            let option = selectedRhythmOption ?? appState.rhythmDurationOptions.first
                            await appState.startSession(
                                activityId: activityId,
                                type: .rhythm,
                                timerMinutes: option?.focusMinutes,
                                breakMinutes: option?.breakMinutes
                            )
                        case .timebound:
                            await appState.startSession(
                                activityId: activityId,
                                type: .timebound,
                                timerMinutes: timeboundMinutes
                            )
                        default:
                            await appState.startSession(
                                activityId: activityId,
                                type: selectedType
                            )
                        }
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(Constants.spacingPage)
        .frame(width: 300)
        .onAppear {
            Task {
                timeboundMinutes = (try? await appState.getPreference(key: PreferenceKey.defaultTimeboundMinutes)).flatMap(Int.init) ?? Constants.defaultTimeboundMinutes
            }
        }
        .syncRhythmSelection($selectedRhythmOption)
    }
}
