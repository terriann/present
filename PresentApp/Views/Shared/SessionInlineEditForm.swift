import SwiftUI
import PresentCore

/// Inline form that replaces a session row for editing activity, start time, and end time.
///
/// Renders inside `ActivitySessionCard` when "Edit Session" is selected from the context menu.
/// Only one session can be edited at a time. Each field saves independently on blur/change.
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
    @State private var noteText: String
    @State private var errorMessage: String?
    @State private var errorFields: Set<ErrorField> = []

    private enum ErrorField: Hashable { case activity, start, end, note }

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
        _noteText = State(initialValue: session.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.spacingCompact) {
            // Top row: Activity, Start, End side by side
            HStack(alignment: .top, spacing: Constants.spacingCard) {
                // Activity picker
                VStack(alignment: .leading, spacing: 2) {
                    Text("Activity")
                        .font(.fieldLabel)
                        .foregroundStyle(errorFields.contains(.activity) ? theme.alert : .secondary)
                    Picker("Activity", selection: $selectedActivityId) {
                        ForEach(appState.popoverActivities) { activity in
                            Text(activity.title).tag(activity.id ?? Int64(-1))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                // Start time
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start")
                        .font(.fieldLabel)
                        .foregroundStyle(errorFields.contains(.start) ? theme.alert : .secondary)
                    DatePicker("Start", selection: $startTime)
                        .datePickerStyle(.stepperField)
                        .labelsHidden()
                        .fixedSize()
                }

                // End time
                VStack(alignment: .leading, spacing: 2) {
                    Text("End")
                        .font(.fieldLabel)
                        .foregroundStyle(errorFields.contains(.end) ? theme.alert : .secondary)
                    DatePicker("End", selection: $endTime, in: ...Date())
                        .datePickerStyle(.stepperField)
                        .labelsHidden()
                        .fixedSize()
                        .disabled(isActive)
                }

                // Paused time
                if session.totalPausedSeconds > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Paused")
                            .font(.fieldLabel)
                            .foregroundStyle(.secondary)
                        Text(TimeFormatting.formatDuration(seconds: session.totalPausedSeconds))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .onChange(of: selectedActivityId) { oldValue, newValue in
                guard newValue != session.activityId else { return }
                saveField { UpdateSessionInput(activityId: newValue) }
            }
            .onChange(of: startTime) { oldValue, newValue in
                guard newValue != session.startedAt else { return }
                saveField { UpdateSessionInput(startedAt: newValue) }
            }
            .onChange(of: endTime) { oldValue, newValue in
                guard !isActive, newValue != session.endedAt else { return }
                saveField { UpdateSessionInput(endedAt: newValue) }
            }

            // Note row
            VStack(alignment: .leading, spacing: 2) {
                Text("Note")
                    .font(.fieldLabel)
                    .foregroundStyle(noteLabelColor)
                MarkdownEditor(text: $noteText, onCommit: { saveNote() })
                    .frame(minHeight: 60, maxHeight: 100)

                if let extracted = liveTicketExtraction {
                    TicketBadge(ticketId: extracted.ticketId, link: extracted.url)
                }
            }

            // Error display
            if let errorMessage {
                Text(errorMessage)
                    .font(.body)
                    .foregroundStyle(theme.alert)
            }
        }
        .padding(Constants.spacingCard)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .onKeyPress(.escape) {
            if hasPendingChanges {
                revertAll()
                return .handled
            }
            onCancel()
            return .handled
        }
    }

    // MARK: - Helpers

    private var noteLabelColor: Color {
        errorFields.contains(.note) ? theme.alert : .secondary
    }

    private var liveTicketExtraction: (url: String, ticketId: String)? {
        TicketExtractor.extractFirstTicketURL(from: noteText)
    }

    private var hasPendingChanges: Bool {
        selectedActivityId != session.activityId
            || startTime != session.startedAt
            || (!isActive && endTime != (session.endedAt ?? Date()))
            || noteText.trimmingCharacters(in: .whitespacesAndNewlines) != (session.note ?? "")
    }

    private func revertAll() {
        selectedActivityId = session.activityId
        startTime = session.startedAt
        endTime = session.endedAt ?? Date()
        noteText = session.note ?? ""
        errorMessage = nil
        errorFields = []
    }

    private func saveNote() {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (session.note ?? "") else { return }
        saveField { UpdateSessionInput(note: trimmed) }
    }

    private func saveField(_ inputBuilder: @escaping () -> UpdateSessionInput) {
        guard let sessionId = session.id else { return }
        errorMessage = nil
        errorFields = []

        Task {
            do {
                try await appState.updateSession(id: sessionId, inputBuilder())
                onSave()
            } catch {
                errorMessage = error.localizedDescription
                errorFields = errorFieldsFrom(error)
            }
        }
    }

    // MARK: - Error Mapping

    /// Which fields the user actually changed — used to scope error highlights.
    private var changedTimeFields: Set<ErrorField> {
        var fields: Set<ErrorField> = []
        if startTime != session.startedAt { fields.insert(.start) }
        if !isActive && endTime != (session.endedAt ?? Date()) { fields.insert(.end) }
        return fields
    }

    private func errorFieldsFrom(_ error: Error) -> Set<ErrorField> {
        if let presentError = error as? PresentError {
            switch presentError {
            case .activityNotFound, .activityIsArchived:
                return [.activity]
            case .sessionOverlap:
                let changed = changedTimeFields
                return changed.isEmpty ? [.start, .end] : changed
            case .invalidInput(let msg):
                if msg.localizedCaseInsensitiveContains("note") {
                    return [.note]
                }
                let mentionsStart = msg.localizedCaseInsensitiveContains("start time")
                let mentionsEnd = msg.localizedCaseInsensitiveContains("end time")
                if mentionsStart && mentionsEnd {
                    return [.start, .end]
                } else if mentionsStart {
                    return [.start]
                } else if mentionsEnd {
                    return [.end]
                }
                let changed = changedTimeFields
                return changed.isEmpty ? [.start, .end] : changed
            default:
                return []
            }
        }
        return []
    }
}
