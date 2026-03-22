import os
import SwiftUI
import PresentCore

/// Lightweight edit form for the active session, shown inline in the menu bar popover
/// or the dashboard active timer panel.
///
/// Supports editing session type, start time, and notes. Saves start time on change,
/// notes on blur/Done. Escape reverts pending changes; Done flushes and dismisses.
struct SessionEditForm: View {
    let session: Session
    let activity: Activity
    var zoomScale: CGFloat = 1.0
    var scaledFont: ((Font.TextStyle, Font.Weight) -> Font)?
    var onSave: () -> Void
    var onCancel: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    @State private var startTime: Date
    @State private var noteText: String
    @State private var errorMessage: String?
    @State private var errorFields: Set<ErrorField> = []
    @State private var showStartDate = false
    @State private var explicitlyClosed = false

    private enum ErrorField: Hashable { case start, note }

    /// Resolves the font — uses the custom scaledFont closure if provided, otherwise system fonts.
    private func font(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        if let scaledFont { return scaledFont(style, weight) }
        return .system(style, weight: weight)
    }

    init(session: Session, activity: Activity, zoomScale: CGFloat = 1.0,
         scaledFont: ((Font.TextStyle, Font.Weight) -> Font)? = nil,
         onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.session = session
        self.activity = activity
        self.zoomScale = zoomScale
        self.scaledFont = scaledFont
        self.onSave = onSave
        self.onCancel = onCancel
        _startTime = State(initialValue: session.startedAt)
        _noteText = State(initialValue: session.note ?? "")
    }

    @State private var isCloseHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.spacingCompact * zoomScale) {
            // Close button
            HStack {
                Spacer()
                Button {
                    explicitlyClosed = true
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(font(.caption, .medium))
                        .foregroundStyle(isCloseHovered ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close edit form")
                .help("Close edit form")
                .onHover { hovering in isCloseHovered = hovering }
            }

            // Session type conversion
            if !activity.isSystem {
                SessionTypeConvertControls(session: session) {
                    onSave()
                }
            }

            // Start time row
            HStack(spacing: Constants.spacingCompact * zoomScale) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Started")
                        .font(font(.caption, .semibold))
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

                Spacer()

                Button("Done") { done() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(font(.caption, .medium))
            }
            .onChange(of: startTime) { _, newValue in
                guard newValue != session.startedAt else { return }
                saveField { UpdateSessionInput(startedAt: newValue) }
            }

            // Note editor
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Label("Note", systemImage: "doc.text")
                        .font(font(.caption, .semibold))
                        .foregroundStyle(errorFields.contains(.note) ? theme.alert : .secondary)
                    Spacer()
                    MarkdownHelpButton()
                }
                MarkdownEditor(text: $noteText, focusOnAppear: false, onCommit: { saveNote() }, onEscape: {
                    if hasPendingChanges {
                        revertAll()
                    } else {
                        explicitlyClosed = true
                        onCancel()
                    }
                })
                .frame(minHeight: 50 * zoomScale, maxHeight: 80 * zoomScale)

                if let extracted = liveTicketExtraction {
                    TicketBadge(ticketId: extracted.ticketId, link: extracted.url,
                                font: font(.caption), scale: zoomScale)
                }
            }

            // Error display
            if let errorMessage {
                Text(errorMessage)
                    .font(font(.caption, .regular))
                    .foregroundStyle(theme.alert)
            }
        }
        .padding(Constants.spacingCard * zoomScale)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, Constants.spacingCard * zoomScale)
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

    private func dateIndicatorButton(date: Date, expanded: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Image(systemName: "calendar")
                    .rotationEffect(.degrees(expanded ? 45 : 0))
                if !Calendar.current.isDate(date, inSameDayAs: Date()) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated)))
                }
            }
            .font(font(.caption, .regular))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var liveTicketExtraction: (url: String, ticketId: String)? {
        guard !activity.isSystem else { return nil }
        return TicketExtractor.extractFirstTicketURL(from: noteText)
    }

    /// Whether the form has unsaved edits.
    ///
    /// `startTime` and `noteText` are `@State` values set from `session` in `init`.
    /// `@State` only writes its initial value on first view creation, so after a
    /// successful save `session` updates via observation but the `@State` values
    /// stay at whatever the user entered. This is fine because:
    /// - On success, both sides match (the saved value equals the user's input).
    /// - On failure, `session` keeps the old value while the `@State` keeps the
    ///   rejected input, so `hasPendingChanges` correctly returns `true`.
    private var hasPendingChanges: Bool {
        startTime != session.startedAt
            || noteText.trimmingCharacters(in: .whitespacesAndNewlines) != (session.note ?? "")
    }

    private func revertAll() {
        startTime = session.startedAt
        noteText = session.note ?? ""
        errorMessage = nil
        errorFields = []
    }

    // MARK: - Save & Dismiss

    private func saveNote() {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (session.note ?? "") else { return }
        saveField { UpdateSessionInput(note: trimmed) }
    }

    private func done() {
        guard let sessionId = session.id else { explicitlyClosed = true; onSave(); return }

        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteChanged = trimmed != (session.note ?? "")

        guard noteChanged else { explicitlyClosed = true; onSave(); return }

        Task {
            do {
                try await appState.updateSession(id: sessionId, UpdateSessionInput(note: trimmed))
            } catch {
                errorMessage = error.localizedDescription
                errorFields = errorFieldsFrom(error)
                return
            }
            explicitlyClosed = true
            onSave()
        }
    }

    private static let logger = Logger(subsystem: "com.present.app", category: "menubar-edit")

    private func flushBufferedChanges() {
        guard let sessionId = session.id else { return }

        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteChanged = trimmed != (session.note ?? "")

        guard noteChanged else { return }

        Task {
            do {
                try await appState.updateSession(id: sessionId, UpdateSessionInput(note: trimmed))
                onSave()
            } catch {
                Self.logger.warning("Failed to flush buffered changes for session \(sessionId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

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

    private func errorFieldsFrom(_ error: Error) -> Set<ErrorField> {
        if let presentError = error as? PresentError {
            switch presentError {
            case .sessionOverlap:
                return [.start]
            case .invalidInput(let msg):
                if msg.localizedCaseInsensitiveContains("note") {
                    return [.note]
                }
                if msg.localizedCaseInsensitiveContains("start time") {
                    return [.start]
                }
                return [.start]
            default:
                return []
            }
        }
        return []
    }
}
