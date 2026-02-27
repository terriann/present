import SwiftUI
import PresentCore

/// Attaches a right-click context menu to session rows.
///
/// - **Active sessions** (running/paused): pause, resume, stop, and delete controls.
///   Deleting an active session stops it first, then removes it.
/// - **Completed/cancelled sessions**: delete only.
struct SessionContextMenuModifier: ViewModifier {
    @Environment(AppState.self) private var appState

    let session: Session
    let activityTitle: String
    var onDelete: (() -> Void)?

    @State private var showingDeleteConfirm = false
    @State private var showingEditSheet = false
    @State private var showingConvertSheet = false

    private var isActive: Bool {
        session.state == .running || session.state == .paused
    }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if isActive {
                    activeSessionControls
                    Divider()
                }

                Button {
                    showingEditSheet = true
                } label: {
                    Label("Edit Note & Link...", systemImage: "square.and.pencil")
                }

                Divider()

                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete Session...", systemImage: "trash")
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                SessionEditSheet(
                    session: session,
                    activityTitle: activityTitle
                )
            }
            .sheet(isPresented: $showingConvertSheet) {
                ConvertToTimeboundSheet()
            }
            .alert("Delete Session?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    Task {
                        if isActive {
                            await performActiveDelete()
                        } else {
                            await performDelete()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(confirmationMessage)
            }
    }

    // MARK: - Active Session Controls

    @ViewBuilder
    private var activeSessionControls: some View {
        if session.state == .running {
            Button {
                Task { await appState.pauseSession() }
            } label: {
                Label("Pause Session", systemImage: "pause.fill")
            }
        }

        if session.state == .paused {
            Button {
                Task { await appState.resumeSession() }
            } label: {
                Label("Resume Session", systemImage: "play.fill")
            }
        }

        // Conversion options (not available for rhythm)
        if session.sessionType == .work {
            Button {
                showingConvertSheet = true
            } label: {
                Label("Convert to Timebound...", systemImage: "timer")
            }
        } else if session.sessionType == .timebound {
            Button {
                Task { await appState.convertSession(ConvertSessionInput(targetType: .work)) }
            } label: {
                Label("Convert to Work Session", systemImage: "infinity")
            }
        }

        Divider()

        Button {
            Task { await appState.stopSession() }
        } label: {
            Label("Stop Session", systemImage: "stop.fill")
        }
    }

    // MARK: - Helpers

    private var confirmationMessage: String {
        if isActive {
            let elapsed = appState.timerElapsedSeconds
            var message = "\"\(activityTitle)\" — active session"
            if elapsed > 0 {
                message += " (\(TimeFormatting.formatDuration(seconds: elapsed)))"
            }
            message += ". This will stop the session and permanently delete it."
            message += " Reports and totals will update. This cannot be undone."
            return message
        }

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

    private func performActiveDelete() async {
        guard let sessionId = session.id else { return }
        do {
            // Stop the active session first, then delete it
            await appState.stopSession()
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
    func sessionContextMenu(
        session: Session,
        activityTitle: String,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        modifier(SessionContextMenuModifier(
            session: session,
            activityTitle: activityTitle,
            onDelete: onDelete
        ))
    }
}
