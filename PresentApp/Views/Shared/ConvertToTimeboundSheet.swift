import SwiftUI
import PresentCore

/// Compact sheet for choosing a duration when converting a work session to timebound.
struct ConvertToTimeboundSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var minutes: Int = 25

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.spacingPage) {
            Text("Convert to Timebound")
                .font(.headline)

            Text("The countdown starts from now. Time already tracked is preserved.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: Constants.spacingCompact) {
                Text("Duration:")
                    .font(.body)
                TextField("", value: $minutes, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                Text("minutes")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Convert") {
                    dismiss()
                    Task {
                        await appState.convertSession(
                            ConvertSessionInput(targetType: .timebound, timerMinutes: minutes)
                        )
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(minutes < 1)
            }
        }
        .padding(Constants.spacingPage)
        .frame(minWidth: 300)
        .onAppear {
            Task {
                minutes = (try? await appState.service.getPreference(key: PreferenceKey.defaultTimeboundMinutes)).flatMap(Int.init) ?? Constants.defaultTimeboundMinutes
            }
        }
    }
}
