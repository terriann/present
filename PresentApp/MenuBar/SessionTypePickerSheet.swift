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
                        Text("\(option.focusMinutes) min (\(option.breakMinutes)m)").tag(Optional(option))
                    }
                }
                .pickerStyle(.segmented)
            } else if selectedType == .timebound {
                HStack {
                    Text("Duration:")
                    TextField("Minutes", value: $timeboundMinutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("min")
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Start") {
                    Task {
                        switch selectedType {
                        case .rhythm:
                            let option = selectedRhythmOption ?? appState.rhythmDurationOptions.first
                            await appState.startSession(
                                activityId: activity.id!,
                                type: .rhythm,
                                timerMinutes: option?.focusMinutes,
                                breakMinutes: option?.breakMinutes
                            )
                        case .timebound:
                            await appState.startSession(
                                activityId: activity.id!,
                                type: .timebound,
                                timerMinutes: timeboundMinutes
                            )
                        default:
                            await appState.startSession(
                                activityId: activity.id!,
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
            if selectedRhythmOption == nil || !appState.rhythmDurationOptions.contains(where: { $0 == selectedRhythmOption }) {
                selectedRhythmOption = appState.rhythmDurationOptions.first
            }
            Task {
                timeboundMinutes = (try? await appState.service.getPreference(key: PreferenceKey.defaultTimeboundMinutes)).flatMap(Int.init) ?? Constants.defaultTimeboundMinutes
            }
        }
    }
}
