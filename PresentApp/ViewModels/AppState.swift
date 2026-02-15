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

    // MARK: - Timer

    var timerElapsedSeconds: Int = 0
    private var timerTask: Task<Void, Never>?

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

    // MARK: - Initialization

    init() {
        do {
            dbManager = try DatabaseManager(path: DatabaseManager.defaultDatabasePath)
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
        service = PresentService(databasePool: dbManager.writer)
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
                startTimer()
            } else {
                currentSession = nil
                currentActivity = nil
                stopTimer()
            }

            let summary = try await service.todaySummary()
            todayTotalSeconds = summary.totalSeconds
            todaySessionCount = summary.sessionCount
            todayActivities = summary.activities

            recentActivities = try await service.recentActivities(limit: 6)
            allActivities = try await service.listActivities(includeArchived: false)
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
            startTimer()
            await refreshAll()
        } catch {
            print("Error starting session: \(error)")
        }
    }

    func pauseSession() async {
        do {
            let session = try await service.pauseSession()
            currentSession = session
            stopTimer()
        } catch {
            print("Error pausing session: \(error)")
        }
    }

    func resumeSession() async {
        do {
            let session = try await service.resumeSession()
            currentSession = session
            startTimer()
        } catch {
            print("Error resuming session: \(error)")
        }
    }

    func stopSession() async {
        do {
            _ = try await service.stopSession()
            currentSession = nil
            currentActivity = nil
            stopTimer()
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
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
        timerElapsedSeconds = 0
    }

    // MARK: - Database Observation

    private func startObservations() {
        observationTask = Task {
            // Poll for changes periodically (works with both DatabasePool and DatabaseQueue)
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
    case log = "Log"
    case reports = "Reports"
    case activities = "Activities"

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
