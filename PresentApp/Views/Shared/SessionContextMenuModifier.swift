import SwiftUI
import PresentCore

/// Attaches a right-click context menu to session rows.
///
/// - **Active sessions** (running/paused): pause, resume, stop, and delete controls.
///   Deleting an active session stops it first, then removes it.
/// - **Completed/cancelled sessions**: edit, repeat, and delete.
struct SessionContextMenuModifier: ViewModifier {
    @Environment(AppState.self) private var appState

    let session: Session
    let activityTitle: String
    var showEditActivity: Bool = true
    var onEdit: ((Int64) -> Void)?
    var onDelete: (() -> Void)?

    @State private var showingDeleteConfirm = false
    @State private var showingConvertSheet = false
    @State private var convertTargetType: SessionType = .timebound

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

                if let onEdit {
                    Button {
                        if let id = session.id { onEdit(id) }
                    } label: {
                        Label("Edit Session", systemImage: "pencil")
                    }
                }

                if !isActive {
                    Button {
                        Task {
                            await appState.startSession(
                                activityId: session.activityId,
                                type: session.sessionType,
                                timerMinutes: session.timerLengthMinutes,
                                breakMinutes: session.breakMinutes
                            )
                        }
                    } label: {
                        Label("Repeat \(session.typeDescription)", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(appState.currentSession != nil)
                }

                if showEditActivity {
                    Divider()

                    Button {
                        appState.navigate(to: .showActivity(session.activityId))
                    } label: {
                        Label("Edit Activity", systemImage: "square.and.pencil")
                    }
                }

                Divider()

                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete Session...", systemImage: "trash")
                }
            }
            .sheet(isPresented: $showingConvertSheet) {
                ConvertSessionSheet(session: session, initialTargetType: convertTargetType)
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

        // Conversion options
        if session.sessionType != .work {
            Button {
                Task { await appState.convertSession(ConvertSessionInput(targetType: .work)) }
            } label: {
                Label("Convert to Work Session", systemImage: "infinity")
            }
        }

        if session.sessionType != .timebound {
            Button {
                convertTargetType = .timebound
                showingConvertSheet = true
            } label: {
                Label("Convert to Timebound...", systemImage: "timer")
            }
        }

        if session.sessionType != .rhythm {
            Button {
                convertTargetType = .rhythm
                showingConvertSheet = true
            } label: {
                Label("Convert to Rhythm...", systemImage: "arrow.triangle.2.circlepath")
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
            try await appState.deleteSession(id: sessionId)
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
            try await appState.deleteSession(id: sessionId)
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
        showEditActivity: Bool = true,
        onEdit: ((Int64) -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        modifier(SessionContextMenuModifier(
            session: session,
            activityTitle: activityTitle,
            showEditActivity: showEditActivity,
            onEdit: onEdit,
            onDelete: onDelete
        ))
    }
}
