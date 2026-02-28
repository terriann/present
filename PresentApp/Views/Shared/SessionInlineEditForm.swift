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
    @State private var noteText: String
    @State private var linkText: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var errorFields: Set<ErrorField> = []
    @FocusState private var focusedField: FocusField?

    private enum ErrorField { case activity, start, end, note, link }
    private enum FocusField { case note, link }

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
        _linkText = State(initialValue: session.link ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.spacingCompact) {
            // Top row: Activity, Start, End side by side
            HStack(alignment: .top, spacing: Constants.spacingCard) {
                // Activity picker
                VStack(alignment: .leading, spacing: 2) {
                    Text("Activity")
                        .font(.caption.bold())
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
                        .font(.caption.bold())
                        .foregroundStyle(errorFields.contains(.start) ? theme.alert : .secondary)
                    DatePicker("Start", selection: $startTime)
                        .datePickerStyle(.stepperField)
                        .labelsHidden()
                        .fixedSize()
                }

                // End time
                VStack(alignment: .leading, spacing: 2) {
                    Text("End")
                        .font(.caption.bold())
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
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(TimeFormatting.formatDuration(seconds: session.totalPausedSeconds))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .onChange(of: selectedActivityId) { clearError() }
            .onChange(of: startTime) { clearError() }
            .onChange(of: endTime) { clearError() }

            // Note and Link row
            HStack(alignment: .top, spacing: Constants.spacingCard) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Note")
                        .font(.caption.bold())
                        .foregroundStyle(noteLabelColor)
                    TextField("Add a note...", text: $noteText)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .note)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Link")
                        .font(.caption.bold())
                        .foregroundStyle(linkLabelColor)
                    TextField("https://...", text: $linkText)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .link)
                    if let ticketId = liveTicketId {
                        HStack(spacing: Constants.spacingTight) {
                            Image(systemName: "ticket")
                                .font(.caption)
                                .accessibilityHidden(true)
                            Text(ticketId)
                                .font(.caption)
                        }
                        .foregroundStyle(theme.accent)
                    }
                }
            }

            // Error display
            if let errorMessage {
                Text(errorMessage)
                    .font(.body)
                    .foregroundStyle(theme.alert)
            }

            // Actions
            HStack(spacing: Constants.spacingCompact) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .disabled(isSaving || !hasChanges)
            }
        }
        .padding(Constants.spacingCard)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
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

    private var noteLabelColor: Color {
        if errorFields.contains(.note) { return theme.alert }
        if focusedField == .note { return theme.accent }
        return .secondary
    }

    private var linkLabelColor: Color {
        if errorFields.contains(.link) { return theme.alert }
        if focusedField == .link { return theme.accent }
        return .secondary
    }

    private var hasChanges: Bool {
        selectedActivityId != session.activityId
            || startTime != session.startedAt
            || (!isActive && endTime != (session.endedAt ?? Date()))
            || noteText.trimmingCharacters(in: .whitespacesAndNewlines) != (session.note ?? "")
            || linkText.trimmingCharacters(in: .whitespacesAndNewlines) != (session.link ?? "")
    }

    private var liveTicketId: String? {
        let trimmed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return TicketExtractor.extractTicketId(from: trimmed)
    }

    private func save() {
        guard let sessionId = session.id else { return }
        isSaving = true
        errorMessage = nil
        errorFields = []

        // Build input with only changed fields
        let trimmedNote = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLink = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteChanged = trimmedNote != (session.note ?? "")
        let linkChanged = trimmedLink != (session.link ?? "")

        let input = UpdateSessionInput(
            note: noteChanged ? trimmedNote : nil,
            link: linkChanged ? trimmedLink : nil,
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
                errorFields = errorFieldsFrom(error)
                isSaving = false
            }
        }
    }

    private func clearError() {
        errorMessage = nil
        errorFields = []
    }

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
                // Only highlight the time fields that were actually changed
                let changed = changedTimeFields
                return changed.isEmpty ? [.start, .end] : changed
            case .invalidInput(let msg):
                if msg.localizedCaseInsensitiveContains("link") {
                    return [.link]
                }
                if msg.localizedCaseInsensitiveContains("note") {
                    return [.note]
                }
                let mentionsStart = msg.localizedCaseInsensitiveContains("start time")
                let mentionsEnd = msg.localizedCaseInsensitiveContains("end time")
                // "Start time must be before end time" or "End time must be after start time"
                // mention both — highlight both fields
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
