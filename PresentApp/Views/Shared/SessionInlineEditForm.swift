import os
import SwiftUI
import PresentCore

/// Inline form that replaces a session row for editing activity, start time, and end time.
///
/// Renders inside `ActivitySessionCard` when "Edit Session" is selected from the context menu.
/// Only one session can be edited at a time. Each field saves independently on blur/change.
/// The form stays open until the user explicitly clicks "Done" or presses Escape.
struct SessionInlineEditForm: View {
    let session: Session
    let activity: Activity
    /// Reference date for the current view. `nil` for multi-day views (weekly/monthly),
    /// a specific date for single-day views (daily/dashboard).
    var timeReferenceDate: Date?
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
    @State private var showStartDate: Bool
    @State private var showEndDate: Bool
    @State private var explicitlyClosed = false

    private enum ErrorField: Hashable { case activity, start, end, note }

    private var isActive: Bool {
        session.state == .running || session.state == .paused
    }

    init(session: Session, activity: Activity, timeReferenceDate: Date? = nil,
         onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.session = session
        self.activity = activity
        self.timeReferenceDate = timeReferenceDate
        self.onSave = onSave
        self.onCancel = onCancel
        _selectedActivityId = State(initialValue: session.activityId)
        _startTime = State(initialValue: session.startedAt)
        _endTime = State(initialValue: session.endedAt ?? Date())
        _noteText = State(initialValue: session.note ?? "")

        // Multi-day views (weekly/monthly): date collapsed by default — the calendar
        // icon and day label are always visible so the user can expand on tap.
        // Single-day views (daily): show only if the time falls on a different day.
        let cal = Calendar.current
        let endedAt = session.endedAt ?? Date()
        if let ref = timeReferenceDate {
            _showStartDate = State(initialValue: !cal.isDate(session.startedAt, inSameDayAs: ref))
            _showEndDate = State(initialValue: !cal.isDate(endedAt, inSameDayAs: ref))
        } else {
            _showStartDate = State(initialValue: false)
            _showEndDate = State(initialValue: false)
        }
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
                    HStack(spacing: Constants.spacingTight) {
                        dateIndicatorButton(date: startTime, expanded: showStartDate) {
                            withAdaptiveAnimation(.easeInOut(duration: 0.2)) {
                                showStartDate.toggle()
                            }
                        }
                        .accessibilityLabel(showStartDate ? "Hide date for start time" : "Show date for start time")
                        .help(showStartDate ? "Hide date for start time" : "Show date for start time")
                        DatePicker("Start", selection: $startTime,
                                   displayedComponents: showStartDate ? [.hourAndMinute, .date] : .hourAndMinute)
                            .datePickerStyle(.stepperField)
                            .labelsHidden()
                            .fixedSize()
                    }
                }

                // End time
                VStack(alignment: .leading, spacing: 2) {
                    Text("End")
                        .font(.fieldLabel)
                        .foregroundStyle(errorFields.contains(.end) ? theme.alert : .secondary)
                    HStack(spacing: Constants.spacingTight) {
                        dateIndicatorButton(date: endTime, expanded: showEndDate) {
                            withAdaptiveAnimation(.easeInOut(duration: 0.2)) {
                                showEndDate.toggle()
                            }
                        }
                        .accessibilityLabel(showEndDate ? "Hide date for end time" : "Show date for end time")
                        .help(showEndDate ? "Hide date for end time" : "Show date for end time")
                        DatePicker("End", selection: $endTime, in: ...Date(),
                                   displayedComponents: showEndDate ? [.hourAndMinute, .date] : .hourAndMinute)
                            .datePickerStyle(.stepperField)
                            .labelsHidden()
                            .fixedSize()
                            .disabled(isActive)
                    }
                }

                // Paused time
                if session.totalPausedSeconds > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Paused", systemImage: "pause.circle")
                            .font(.fieldLabel)
                            .foregroundStyle(.secondary)
                        Text(TimeFormatting.formatDuration(seconds: session.totalPausedSeconds))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Done") { done() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            // Activity change is buffered until Done — auto-saving it would move the
            // session to a different group mid-edit, causing the form to jump or vanish.
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
                HStack {
                    Label("Note", systemImage: "doc.text")
                        .font(.fieldLabel)
                        .foregroundStyle(noteLabelColor)
                    Spacer()
                    MarkdownHelpButton()
                }
                MarkdownEditor(text: $noteText, focusOnAppear: true, onCommit: { saveNote() }, onEscape: {
                    if hasPendingChanges {
                        revertAll()
                    } else {
                        onCancel()
                    }
                })
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
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: Constants.cornerRadiusCard))
        .onKeyPress(.escape) {
            if hasPendingChanges {
                revertAll()
                return .handled
            }
            explicitlyClosed = true
            onCancel()
            return .handled
        }
        .onDisappear {
            guard !explicitlyClosed else { return }
            flushBufferedChanges()
        }
    }

    // MARK: - Subviews

    /// Calendar icon with optional day-name label, shown to the left of the time picker.
    /// The icon is always visible so users can toggle the date component. The day label
    /// appears only when the time falls on a different day (daily view) or always (multi-day view).
    private func dateIndicatorButton(date: Date, expanded: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Image(systemName: "calendar")
                    .rotationEffect(.degrees(expanded ? 45 : 0))
                if shouldShowDateLabel(for: date) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated)))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    /// Whether the day-name label should appear next to the calendar icon.
    /// Multi-day views (weekly/monthly): always. Single-day views: only when the time
    /// falls on a different day than the reference date.
    private func shouldShowDateLabel(for date: Date) -> Bool {
        guard let ref = timeReferenceDate else { return true }
        return !Calendar.current.isDate(date, inSameDayAs: ref)
    }

    // MARK: - Helpers

    private var noteLabelColor: Color {
        errorFields.contains(.note) ? theme.alert : .secondary
    }

    private var liveTicketExtraction: (url: String, ticketId: String)? {
        guard !activity.isSystem else { return nil }
        return TicketExtractor.extractFirstTicketURL(from: noteText)
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

    // MARK: - Save & Dismiss

    /// Save the note if changed (on blur). Does not dismiss the form.
    private func saveNote() {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (session.note ?? "") else { return }
        saveField { UpdateSessionInput(note: trimmed) }
    }

    /// Flush buffered changes (activity, note) and dismiss the form.
    ///
    /// Activity and note are the two fields that aren't auto-saved: activity is buffered
    /// to prevent the form from jumping between groups, and note saves on blur but may
    /// have unsaved text if the user clicks Done without blurring the editor first.
    private func done() {
        guard let sessionId = session.id else { explicitlyClosed = true; onSave(); return }

        let activityChanged = selectedActivityId != session.activityId
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteChanged = trimmed != (session.note ?? "")

        guard activityChanged || noteChanged else { explicitlyClosed = true; onSave(); return }

        var input = UpdateSessionInput()
        if activityChanged { input.activityId = selectedActivityId }
        if noteChanged { input.note = trimmed }

        Task {
            do {
                try await appState.updateSession(id: sessionId, input)
            } catch {
                errorMessage = error.localizedDescription
                errorFields = errorFieldsFrom(error)
                return
            }
            explicitlyClosed = true
            onSave()
        }
    }

    private static let logger = Logger(subsystem: "com.present.app", category: "session")

    /// Flush buffered changes (activity, note) when the form disappears without explicit save/cancel.
    /// Time fields auto-save via onChange so they are not included here.
    /// Logs on failure for diagnostics — the form is already gone so the user cannot retry.
    private func flushBufferedChanges() {
        guard let sessionId = session.id else { return }

        let activityChanged = selectedActivityId != session.activityId
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteChanged = trimmed != (session.note ?? "")

        guard activityChanged || noteChanged else { return }

        var input = UpdateSessionInput()
        if activityChanged { input.activityId = selectedActivityId }
        if noteChanged { input.note = trimmed }

        Task {
            do {
                try await appState.updateSession(id: sessionId, input)
                // The form is already gone — trigger onSave to refresh the parent's data
                // so the row immediately reflects the saved changes.
                onSave()
            } catch {
                Self.logger.warning("Failed to flush buffered changes for session \(sessionId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Save a single field change. Shows errors inline but does not dismiss the form.
    private func saveField(_ inputBuilder: @escaping () -> UpdateSessionInput) {
        guard let sessionId = session.id else { return }
        errorMessage = nil
        errorFields = []

        Task {
            do {
                try await appState.updateSession(id: sessionId, inputBuilder())
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
