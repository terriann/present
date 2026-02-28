import SwiftUI
import PresentCore

/// Inline form that replaces a session row for editing activity, start time, and end time.
///
/// Renders inside `ActivitySessionCard` when "Edit Session" is selected from the context menu.
/// Only one session can be edited at a time.
struct SessionInlineEditForm: View {
    let session: Session
    let activity: Activity
    var onSave: () -> Void
    var onCancel: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    @State private var selectedActivityId: Int64
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isActive: Bool {
        session.state == .running || session.state == .paused
    }

    init(session: Session, activity: Activity, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.session = session
        self.activity = activity
        self.onSave = onSave
        self.onCancel = onCancel
        _selectedActivityId = State(initialValue: session.activityId)
        _startTime = State(initialValue: session.startedAt)
        _endTime = State(initialValue: session.endedAt ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.spacingCompact) {
            // Activity picker
            HStack {
                Text("Activity")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Activity", selection: $selectedActivityId) {
                    ForEach(appState.popoverActivities) { activity in
                        Text(activity.title).tag(activity.id ?? Int64(-1))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            // Start time
            HStack {
                Text("Start")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer()
                DatePicker("Start", selection: $startTime)
                    .labelsHidden()
                    .fixedSize()
            }

            // End time
            HStack {
                Text("End")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer()
                DatePicker("End", selection: $endTime)
                    .labelsHidden()
                    .fixedSize()
                    .disabled(isActive)
            }

            // Paused time (read-only, shown only when relevant)
            if session.totalPausedSeconds > 0 {
                HStack {
                    Text("Paused")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(TimeFormatting.formatDuration(seconds: session.totalPausedSeconds))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            // Error display
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(theme.alert)
            }

            // Actions
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .disabled(isSaving || !hasChanges)
            }
        }
        .padding(Constants.spacingCard)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(theme.accent.opacity(0.3), lineWidth: 1)
        )
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
        .onKeyPress(.return) {
            guard !isSaving && hasChanges else { return .ignored }
            save()
            return .handled
        }
    }

    // MARK: - Helpers

    private var hasChanges: Bool {
        selectedActivityId != session.activityId
            || startTime != session.startedAt
            || (!isActive && endTime != (session.endedAt ?? Date()))
    }

    private func save() {
        guard let sessionId = session.id else { return }
        isSaving = true
        errorMessage = nil

        // Build input with only changed fields
        let input = UpdateSessionInput(
            activityId: selectedActivityId != session.activityId ? selectedActivityId : nil,
            startedAt: startTime != session.startedAt ? startTime : nil,
            endedAt: !isActive && endTime != session.endedAt ? endTime : nil
        )

        Task {
            do {
                try await appState.updateSession(id: sessionId, input)
                onSave()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}
