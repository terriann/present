import SwiftUI
import PresentCore
import GRDB
import Combine

@MainActor @Observable
final class AppState {
    // MARK: - Published State

    var currentSession: Session?
    var currentActivity: Activity?
    var todayTotalSeconds: Int = 0
    var todaySessionCount: Int = 0
    var todayActivities: [ActivitySummary] = []
    var recentActivities: [Activity] = []
    var allActivities: [Activity] = []
    var allTags: [Tag] = []
    var recentSessionSuggestion: (session: Session, activity: Activity)?

    // MARK: - Timer

    var timerElapsedSeconds: Int = 0
    private var timerTask: Task<Void, Never>?
    private var timerCompletionHandled = false

    // MARK: - Break Suggestion

    var showBreakSuggestion = false
    var suggestedBreakMinutes: Int = 5
    var isLongBreak = false

    // MARK: - Navigation

    var selectedSidebarItem: SidebarItem = .dashboard

    // MARK: - Services

    private(set) var service: PresentService
    private let dbManager: DatabaseManager
    private var ipcServer: IPCServer?
    private var observationTask: Task<Void, Never>?

    // MARK: - Computed Properties

    var menuBarIcon: String {
        guard let session = currentSession else {
            return "clock"
        }
        switch session.state {
        case .running: return "play.circle.fill"
        case .paused: return "pause.circle.fill"
        default: return "clock"
        }
    }

    var menuBarTimerText: String? {
        guard let session = currentSession, session.state == .running || session.state == .paused else {
            return nil
        }
        return formattedTimerValue
    }

    var formattedTimerValue: String {
        guard let session = currentSession else { return "0:00" }

        // For countdown timers, show remaining time
        if let timerMinutes = session.timerLengthMinutes,
           session.sessionType == .rhythm || session.sessionType == .timebound {
            let totalSeconds = timerMinutes * 60
            let remaining = max(0, totalSeconds - timerElapsedSeconds)
            return TimeFormatting.formatTimer(seconds: remaining)
        }

        // For work sessions, show elapsed time
        return TimeFormatting.formatTimer(seconds: timerElapsedSeconds)
    }

    var isSessionActive: Bool {
        guard let session = currentSession else { return false }
        return session.state == .running || session.state == .paused
    }

    var isSessionRunning: Bool {
        currentSession?.state == .running
    }

    // MARK: - Initialization

    init() {
        do {
            dbManager = try DatabaseManager(path: DatabaseManager.defaultDatabasePath)
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
        service = PresentService(databasePool: dbManager.writer)
        NotificationManager.shared.requestPermission()
        SoundManager.shared.configure(service: service)
        startObservations()
        startIPCServer()
        loadInitialData()
    }

    // MARK: - Data Loading

    private func loadInitialData() {
        Task {
            await refreshAll()
        }
    }

    func refreshAll() async {
        do {
            if let (session, activity) = try await service.currentSession() {
                currentSession = session
                currentActivity = activity
                if session.state == .running, timerTask == nil {
                    startTimer()
                } else if session.state == .paused {
                    // Use fixed dates only — no Date() calls that cause rounding jitter
                    if let pausedAt = session.lastPausedAt {
                        let activeTime = Int(pausedAt.timeIntervalSince(session.startedAt)) - session.totalPausedSeconds
                        timerElapsedSeconds = max(0, activeTime)
                    }
                }
            } else {
                currentSession = nil
                currentActivity = nil
                stopTimer()
            }

            let summary = try await service.todaySummary()
            todayTotalSeconds = summary.totalSeconds
            todaySessionCount = summary.sessionCount
            todayActivities = summary.activities

            if currentSession == nil {
                let since = Date().addingTimeInterval(-3 * 60 * 60)
                recentSessionSuggestion = try await service.lastCompletedSession(since: since)
            } else {
                recentSessionSuggestion = nil
            }

            recentActivities = try await service.recentActivities(limit: 6)
            allActivities = try await service.listActivities(includeArchived: true)
            allTags = try await service.listTags()
        } catch {
            print("Error refreshing data: \(error)")
        }
    }

    // MARK: - Session Actions

    func startSession(activityId: Int64, type: SessionType, timerMinutes: Int? = nil) async {
        do {
            let session = try await service.startSession(
                activityId: activityId,
                type: type,
                timerMinutes: timerMinutes
            )
            currentSession = session
            currentActivity = try await service.getActivity(id: activityId)
            timerCompletionHandled = false
            startTimer()
            SoundManager.shared.play(.blow)
            await refreshAll()
        } catch {
            print("Error starting session: \(error)")
        }
    }

    func pauseSession() async {
        do {
            let session = try await service.pauseSession()
            currentSession = session
            stopTimer(resetElapsed: false)
        } catch {
            print("Error pausing session: \(error)")
        }
    }

    func resumeSession() async {
        do {
            let session = try await service.resumeSession()
            currentSession = session
            startTimer()
            SoundManager.shared.play(.blow)
        } catch {
            print("Error resuming session: \(error)")
        }
    }

    func stopSession() async {
        do {
            let stoppedSession = try await service.stopSession()
            let activity = currentActivity
            currentSession = nil
            currentActivity = nil
            stopTimer()

            // For rhythm sessions, suggest a break
            if stoppedSession.sessionType == .rhythm, let index = stoppedSession.rhythmSessionIndex {
                await suggestBreak(sessionIndex: index)
            }

            _ = activity
            await refreshAll()
        } catch {
            print("Error stopping session: \(error)")
        }
    }

    func cancelSession() async {
        do {
            try await service.cancelSession()
            currentSession = nil
            currentActivity = nil
            stopTimer()
            SoundManager.shared.play(.dip)
            await refreshAll()
        } catch {
            print("Error cancelling session: \(error)")
        }
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        guard let session = currentSession else { return }

        let elapsed = Int(Date().timeIntervalSince(session.startedAt)) - session.totalPausedSeconds
        timerElapsedSeconds = max(0, elapsed)

        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                guard let session = self.currentSession, session.state == .running else { return }
                let elapsed = Int(Date().timeIntervalSince(session.startedAt)) - session.totalPausedSeconds
                self.timerElapsedSeconds = max(0, elapsed)

                // Check for countdown timer completion
                if !self.timerCompletionHandled,
                   let timerMinutes = session.timerLengthMinutes,
                   (session.sessionType == .rhythm || session.sessionType == .timebound) {
                    let totalSeconds = timerMinutes * 60
                    if self.timerElapsedSeconds >= totalSeconds {
                        self.timerCompletionHandled = true
                        await self.handleTimerCompletion()
                    }
                }
            }
        }
    }

    private func stopTimer(resetElapsed: Bool = true) {
        timerTask?.cancel()
        timerTask = nil
        if resetElapsed {
            timerElapsedSeconds = 0
        }
    }

    private func handleTimerCompletion() async {
        guard let activity = currentActivity, let session = currentSession else { return }

        // Send notification and play completion sound
        NotificationManager.shared.sendTimerCompleted(
            activityTitle: activity.title,
            sessionType: session.sessionType
        )
        SoundManager.shared.play(.shimmer)

        // Auto-stop the session
        await stopSession()
    }

    // MARK: - Break Suggestions

    private func suggestBreak(sessionIndex: Int) async {
        let cycleLength: Int
        if let val = try? await service.getPreference(key: PreferenceKey.rhythmCycleLength) {
            cycleLength = Int(val) ?? Constants.rhythmCycleLength
        } else {
            cycleLength = Constants.rhythmCycleLength
        }
        let isLong = sessionIndex >= cycleLength

        let breakKey = isLong ? PreferenceKey.longBreakMinutes : PreferenceKey.shortBreakMinutes
        let defaultBreak = isLong ? Constants.longBreakMinutes : Constants.shortBreakMinutes
        let breakMinutes: Int
        if let val = try? await service.getPreference(key: breakKey) {
            breakMinutes = Int(val) ?? defaultBreak
        } else {
            breakMinutes = defaultBreak
        }

        self.isLongBreak = isLong
        self.suggestedBreakMinutes = breakMinutes
        self.showBreakSuggestion = true

        SoundManager.shared.play(.approach)
        NotificationManager.shared.sendBreakSuggestion(isLongBreak: isLong, breakMinutes: breakMinutes)
    }

    func dismissBreakSuggestion() {
        showBreakSuggestion = false
    }

    // MARK: - Database Observation

    private func startObservations() {
        observationTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                await refreshAll()
            }
        }
    }

    // MARK: - IPC

    private func startIPCServer() {
        ipcServer = IPCServer { _ in
            Task { @MainActor in
                // Refresh handled by periodic polling
            }
        }
        try? ipcServer?.start()
    }

    // MARK: - Dock Icon

    func showDockIcon(_ show: Bool) {
        if show {
            NSApplication.shared.setActivationPolicy(.regular)
        } else {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case activities = "Activities"
    case reports = "Reports"
    case log = "Log"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .log: return "list.bullet.clipboard"
        case .reports: return "chart.bar"
        case .activities: return "tray.full"
        }
    }
}
