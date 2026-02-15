import SwiftUI
import PresentCore

struct SessionTypePickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let activity: Activity
    @State private var selectedType: SessionType = .work
    @State private var timerMinutes: Int = 25

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
                Picker("Duration", selection: $timerMinutes) {
                    Text("25 min").tag(25)
                    Text("30 min").tag(30)
                    Text("45 min").tag(45)
                }
                .pickerStyle(.segmented)
            } else if selectedType == .timebound {
                HStack {
                    Text("Duration:")
                    TextField("Minutes", value: $timerMinutes, format: .number)
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
                        let minutes: Int? = (selectedType == .rhythm || selectedType == .timebound) ? timerMinutes : nil
                        await appState.startSession(activityId: activity.id!, type: selectedType, timerMinutes: minutes)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}
