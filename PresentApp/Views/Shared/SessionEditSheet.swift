import SwiftUI
import PresentCore

/// Sheet for editing a session's note and link.
struct SessionEditSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss

    let session: Session
    let activityTitle: String

    @State private var noteText: String = ""
    @State private var linkText: String = ""
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.spacingPage) {
            // Header
            Text("Edit Session")
                .font(.headline)

            Text("\(activityTitle) \u{2014} \(TimeFormatting.formatDate(session.startedAt))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Note field
            VStack(alignment: .leading, spacing: Constants.spacingTight) {
                Text("Note")
                    .font(.dataLabel)

                TextEditor(text: $noteText)
                    .font(.body)
                    .frame(minHeight: 80, maxHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(Constants.spacingCompact)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            }

            // Link field
            VStack(alignment: .leading, spacing: Constants.spacingTight) {
                Text("Link")
                    .font(.dataLabel)

                TextField("https://...", text: $linkText)
                    .textFieldStyle(.roundedBorder)

                if let ticketId = liveTicketId {
                    HStack(spacing: Constants.spacingTight) {
                        Image(systemName: "ticket")
                            .font(.caption)
                        Text(ticketId)
                            .font(.caption)
                    }
                    .foregroundStyle(theme.accent)
                }
            }

            // Actions
            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
            }
        }
        .padding(Constants.spacingPage)
        .frame(minWidth: 360)
        .onAppear {
            noteText = session.note ?? ""
            linkText = session.link ?? ""
        }
    }

    // MARK: - Helpers

    private var liveTicketId: String? {
        let trimmed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return TicketExtractor.extractTicketId(from: trimmed)
    }

    private func save() {
        isSaving = true
        let noteValue = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let linkValue = linkText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Determine what changed
        let noteChanged = noteValue != (session.note ?? "")
        let linkChanged = linkValue != (session.link ?? "")

        guard noteChanged || linkChanged else {
            dismiss()
            return
        }

        let input = UpdateSessionInput(
            note: noteChanged ? noteValue : nil,
            link: linkChanged ? linkValue : nil
        )

        guard let sessionId = session.id else { return }

        Task {
            do {
                try await appState.updateSession(id: sessionId, input)
                dismiss()
            } catch {
                appState.showError(error, context: "Could not update session")
                isSaving = false
            }
        }
    }
}
