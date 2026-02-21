import SwiftUI
import PresentCore
import GRDB
import Combine

struct AppError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor @Observable
final class AppState {
    // MARK: - Published State

    var currentSession: Session?
    var currentActivity: Activity?
    var todayTotalSeconds: Int = 0
    var todaySessionCount: Int = 0
    var todayActivities: [ActivitySummary] = []
    var weeklySummary: WeeklySummary?
    var weekStartDay: Int = 1
    var recentActivities: [Activity] = []
    var allActivities: [Activity] = []
    var allTags: [Tag] = []
    var recentSessionSuggestion: (session: Session, activity: Activity)?
    var rhythmDurationOptions: [RhythmOption] = Constants.defaultRhythmDurationOptions

    // MARK: - Timer

    var timerElapsedSeconds: Int = 0
    private var timerTask: Task<Void, Never>?
    private var timerCompletionHandled = false

    // MARK: - Completed Timer Linger

    var completedTimerText: String?
    var isCompletedTimerFading: Bool = false
    private var completedTimerLingerTask: Task<Void, Never>?

    // MARK: - Break Suggestion

    var showBreakSuggestion = false
    var suggestedBreakMinutes: Int = 5
    var isLongBreak = false

    // MARK: - Error Feedback

    var presentedError: AppError?

    // MARK: - Navigation

    var selectedSidebarItem: SidebarItem = .dashboard
    var navigateToActivityId: Int64?

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
        if let session = currentSession, session.state == .running || session.state == .paused {
            return formattedTimerValue
        }
        return completedTimerText
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

            if let weekStartPref = try? await service.getPreference(key: PreferenceKey.weekStartDay) {
                weekStartDay = PreferenceKey.parseWeekStartDay(weekStartPref)
            }
            let weekly = try await service.weeklySummary(weekOf: Date(), includeArchived: false, weekStartDay: weekStartDay)
            if weekly != weeklySummary { weeklySummary = weekly }

            if currentSession == nil {
                let since = Date().addingTimeInterval(-3 * 60 * 60)
                recentSessionSuggestion = try await service.lastCompletedSession(since: since)
            } else {
                recentSessionSuggestion = nil
            }

            recentActivities = try await service.recentActivities(limit: 6)
            allActivities = try await service.listActivities(includeArchived: true)
            allTags = try await service.listTags()

            if let optionsStr = try? await service.getPreference(key: PreferenceKey.rhythmDurationOptions) {
                let parsed: [RhythmOption] = PreferenceKey.parseRhythmOptions(optionsStr)
                rhythmDurationOptions = parsed.isEmpty ? Constants.defaultRhythmDurationOptions : parsed
            }
        } catch {
            print("Error refreshing data: \(error)")
        }
    }

    // MARK: - Session Actions

    func startSession(activityId: Int64, type: SessionType, timerMinutes: Int? = nil, breakMinutes: Int? = nil) async {
        clearCompletedTimerLinger()
        do {
            let session = try await service.startSession(
                activityId: activityId,
                type: type,
                timerMinutes: timerMinutes,
                breakMinutes: breakMinutes
            )
            currentSession = session
            currentActivity = try await service.getActivity(id: activityId)
            timerCompletionHandled = false
            startTimer()
            SoundManager.shared.play(.blow)
            await refreshAll()
        } catch {
            showError(error, context: "Could not start session")
        }
    }

    func pauseSession() async {
        do {
            let session = try await service.pauseSession()
            currentSession = session
            stopTimer(resetElapsed: false)
        } catch {
            showError(error, context: "Could not pause session")
        }
    }

    func resumeSession() async {
        do {
            let session = try await service.resumeSession()
            currentSession = session
            startTimer()
            SoundManager.shared.play(.blow)
        } catch {
            showError(error, context: "Could not resume session")
        }
    }

    func stopSession() async {
        let finalText = formattedTimerValue

        do {
            let stoppedSession = try await service.stopSession()
            currentSession = nil
            currentActivity = nil
            stopTimer()

            // Start linger unless handleTimerCompletion already did
            if completedTimerText == nil {
                startCompletedTimerLinger(text: finalText, isCountdown: false)
            }

            // For rhythm sessions, suggest a break
            if stoppedSession.sessionType == .rhythm, let index = stoppedSession.rhythmSessionIndex {
                await suggestBreak(session: stoppedSession, sessionIndex: index)
            }

            await refreshAll()
        } catch {
            showError(error, context: "Could not stop session")
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
            showError(error, context: "Could not cancel session")
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

        let finalText = formattedTimerValue
        let isCountdown = session.sessionType == .rhythm || session.sessionType == .timebound

        // Send notification and play completion sound
        NotificationManager.shared.sendTimerCompleted(
            activityTitle: activity.title,
            sessionType: session.sessionType,
            playSound: SoundManager.shared.isEnabled
        )
        SoundManager.shared.play(.shimmer)

        // Start linger BEFORE stopSession so it doesn't get overwritten
        startCompletedTimerLinger(text: finalText, isCountdown: isCountdown)

        // Auto-stop the session
        await stopSession()
    }

    // MARK: - Completed Timer Linger

    private func startCompletedTimerLinger(text: String, isCountdown: Bool) {
        clearCompletedTimerLinger()
        completedTimerText = text

        isCompletedTimerFading = false

        completedTimerLingerTask = Task {
            try? await Task.sleep(for: .seconds(Constants.completedTimerLingerSeconds))
            guard !Task.isCancelled else { return }

            isCompletedTimerFading = true
            completedTimerText = nil

            clearCompletedTimerLinger()
        }
    }

    private func clearCompletedTimerLinger() {
        completedTimerLingerTask?.cancel()
        completedTimerLingerTask = nil
        completedTimerText = nil

        isCompletedTimerFading = false
    }

    // MARK: - Break Suggestions

    private func suggestBreak(session: Session, sessionIndex: Int) async {
        let cycleLength: Int
        if let val = try? await service.getPreference(key: PreferenceKey.rhythmCycleLength) {
            cycleLength = Int(val) ?? Constants.rhythmCycleLength
        } else {
            cycleLength = Constants.rhythmCycleLength
        }
        let isLong = sessionIndex >= cycleLength

        let breakMinutes: Int
        if isLong {
            // Long break: use global preference
            if let val = try? await service.getPreference(key: PreferenceKey.longBreakMinutes) {
                breakMinutes = Int(val) ?? Constants.longBreakMinutes
            } else {
                breakMinutes = Constants.longBreakMinutes
            }
        } else {
            // Short break: use session's paired break duration, fall back to default
            breakMinutes = session.breakMinutes ?? Constants.defaultShortBreakMinutes
        }

        self.isLongBreak = isLong
        self.suggestedBreakMinutes = breakMinutes
        self.showBreakSuggestion = true

        SoundManager.shared.play(.approach)
        NotificationManager.shared.sendBreakSuggestion(isLongBreak: isLong, breakMinutes: breakMinutes, playSound: SoundManager.shared.isEnabled)
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

    // MARK: - Error Feedback

    func showError(_ error: Error, context: String? = nil) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        presentedError = AppError(
            title: context ?? "Something went wrong",
            message: message
        )
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

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .reports: return "chart.bar"
        case .activities: return "tray.full"
        }
    }
}
