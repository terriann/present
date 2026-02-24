import SwiftUI
import PresentCore

/// Attaches a right-click context menu and confirmation alert for deleting a session.
/// Only shows the delete option for completed or cancelled sessions.
struct SessionDeleteModifier: ViewModifier {
    @Environment(AppState.self) private var appState

    let session: Session
    let activityTitle: String
    var onDelete: (() -> Void)?

    @State private var showingDeleteConfirm = false

    private var isDeletable: Bool {
        session.state == .completed || session.state == .cancelled
    }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if isDeletable {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete Session...", systemImage: "trash")
                    }
                }
            }
            .alert("Delete Session?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    Task {
                        await performDelete()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(confirmationMessage)
            }
    }

    // MARK: - Helpers

    private var confirmationMessage: String {
        let date = TimeFormatting.formatDate(session.startedAt)
        var message = "\"\(activityTitle)\" on \(date)"
        if let seconds = session.durationSeconds, seconds > 0 {
            message += " (\(TimeFormatting.formatDuration(seconds: seconds)))"
        }
        message += ". Reports and totals will update. This cannot be undone."
        return message
    }

    private func performDelete() async {
        guard let sessionId = session.id else { return }
        do {
            try await appState.service.deleteSession(id: sessionId)
            SoundManager.shared.play(.dip)
            await appState.refreshAll()
            onDelete?()
        } catch {
            appState.showError(error, context: "Could not delete session")
        }
    }
}

extension View {
    func sessionDeletable(
        session: Session,
        activityTitle: String,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        modifier(SessionDeleteModifier(
            session: session,
            activityTitle: activityTitle,
            onDelete: onDelete
        ))
    }
}
