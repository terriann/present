import SwiftUI
import PresentCore
import GRDB
import Combine

enum ErrorScene {
    case mainWindow
    case menuBar
    case settings
}

struct AppError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let scene: ErrorScene
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

    // MARK: - Timer (forwarded from TimerManager)

    private(set) var timer: TimerManager!

    var timerElapsedSeconds: Int { timer.timerElapsedSeconds }
    var completedTimerText: String? { timer.completedTimerText }
    var isCompletedTimerFading: Bool { timer.isCompletedTimerFading }
    var timerCompletionContext: TimerCompletionContext? {
        get { timer.timerCompletionContext }
        set { timer.timerCompletionContext = newValue }
    }
    var breakPrecedingContext: (activityId: Int64, title: String, timerMinutes: Int, breakMinutes: Int)? {
        get { timer.breakPrecedingContext }
        set { timer.breakPrecedingContext = newValue }
    }

    // MARK: - Zoom (forwarded from ZoomManager)

    private(set) var zoom: ZoomManager!

    var zoomScale: CGFloat { zoom.zoomScale }
    var canZoomIn: Bool { zoom.canZoomIn }
    var canZoomOut: Bool { zoom.canZoomOut }
    var isDefaultZoom: Bool { zoom.isDefaultZoom }

    func zoomIn() { zoom.zoomIn() }
    func zoomOut() { zoom.zoomOut() }
    func resetZoom() { zoom.resetZoom() }

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
        timer.formattedTimerValue
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
        zoom = ZoomManager(service: service)
        timer = TimerManager(service: service)
        timer.onCountdownCompleted = { [weak self] in
            await self?.handleTimerCompletion()
        }
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
                timer.currentSession = session
                if session.state == .running, !timer.isTimerRunning {
                    timer.startTimer(session: session)
                } else if session.state == .paused {
                    timer.syncPausedElapsed(session: session)
                }
            } else {
                currentSession = nil
                currentActivity = nil
                timer.currentSession = nil
                timer.stopTimer()
            }

            let summary = try await service.todaySummary()
            todayTotalSeconds = summary.totalSeconds
            todaySessionCount = summary.sessionCount
            todayActivities = summary.activities

            if let weekStartPref = try? await service.getPreference(key: PreferenceKey.weekStartDay) {
                weekStartDay = PreferenceKey.parseWeekStartDay(weekStartPref)
            }
            let weekly = try await service.weeklySummary(weekOf: Date(), includeArchived: false, weekStartDay: weekStartDay, roundToMinute: true)
            if weekly != weeklySummary { weeklySummary = weekly }

            if currentSession == nil {
                let since = Date().addingTimeInterval(-3 * 60 * 60)
                recentSessionSuggestion = try await service.lastCompletedSession(since: since)
            } else {
                recentSessionSuggestion = nil
            }

            recentActivities = try await service.recentActivities(limit: 6)
            allActivities = try await service.listActivities(includeArchived: true, includeSystem: true)
            allTags = try await service.listTags()

            await zoom.loadFromPreferences()

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
        timer.clearCompletedTimerLinger()
        timerCompletionContext = nil
        do {
            let session = try await service.startSession(
                activityId: activityId,
                type: type,
                timerMinutes: timerMinutes,
                breakMinutes: breakMinutes
            )
            currentSession = session
            currentActivity = try await service.getActivity(id: activityId)
            timer.startTimer(session: session)
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
            timer.currentSession = session
            timer.stopTimer(resetElapsed: false)
        } catch {
            showError(error, context: "Could not pause session")
        }
    }

    func resumeSession() async {
        do {
            let session = try await service.resumeSession()
            currentSession = session
            timer.startTimer(session: session)
            SoundManager.shared.play(.blow)
        } catch {
            showError(error, context: "Could not resume session")
        }
    }

    func stopSession() async {
        let finalText = timer.formattedTimerValue

        do {
            _ = try await service.stopSession()
            currentSession = nil
            currentActivity = nil
            timer.currentSession = nil
            timer.stopTimer()

            // Start linger unless handleTimerCompletion already did
            if completedTimerText == nil {
                timer.startCompletedTimerLinger(text: finalText, isCountdown: false)
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
            timer.currentSession = nil
            timer.stopTimer()
            SoundManager.shared.play(.dip)
            await refreshAll()
        } catch {
            showError(error, context: "Could not cancel session")
        }
    }

    // MARK: - Timer Completion (coordination)

    private func handleTimerCompletion() async {
        guard let activity = currentActivity, let session = currentSession else { return }

        let finalText = timer.formattedTimerValue
        let isCountdown = session.sessionType == .rhythm || session.sessionType == .timebound
        let timerMinutes = session.timerLengthMinutes ?? 0

        // Build completion context BEFORE stopping the session
        let completionType: TimerCompletionContext.CompletionType?
        if activity.isSystem {
            // Break session ended — restore from disk if lost (e.g., after crash)
            timer.restoreBreakContextIfNeeded()
            if let ctx = breakPrecedingContext {
                completionType = .rhythmBreakExpiry(
                    previousActivityId: ctx.activityId,
                    previousActivityTitle: ctx.title,
                    previousTimerMinutes: ctx.timerMinutes,
                    previousBreakMinutes: ctx.breakMinutes
                )
            } else {
                // Standalone timebound break — find most recent non-break session
                let recent = try? await service.lastCompletedNonSystemSession(
                    since: Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()
                )
                completionType = .timeboundBreakExpiry(
                    recentActivityId: recent?.1.id,
                    recentActivityTitle: recent?.1.title,
                    recentTimerMinutes: recent?.0.timerLengthMinutes,
                    recentSessionType: recent?.0.sessionType
                )
            }
        } else if session.sessionType == .rhythm, let index = session.rhythmSessionIndex {
            let breakMins = await timer.resolveBreakMinutes(session: session, sessionIndex: index)
            let cycleLength = await timer.resolveCycleLength()
            let isLong = index >= cycleLength
            completionType = .rhythmFocusExpiry(breakMinutes: breakMins, isLongBreak: isLong)
        } else {
            completionType = .timeboundExpiry
        }

        // Send notification and play completion sound
        NotificationManager.shared.sendTimerCompleted(
            activityTitle: activity.title,
            sessionType: session.sessionType,
            playSound: SoundManager.shared.isEnabled
        )
        SoundManager.shared.play(.shimmer)

        // Start linger BEFORE stopSession so it doesn't get overwritten
        timer.startCompletedTimerLinger(text: finalText, isCountdown: isCountdown)

        // Auto-stop the session
        await stopSession()

        // Show floating alert (skip if context couldn't be determined)
        if let completionType {
            timerCompletionContext = TimerCompletionContext(
                completionType: completionType,
                activityId: activity.id ?? 0,
                activityTitle: activity.title,
                durationFormatted: finalText,
                timerMinutes: timerMinutes
            )
        }
    }

    // MARK: - Timer Completion Alert Actions

    func dismissTimerAlert() {
        timerCompletionContext = nil
        breakPrecedingContext = nil
    }

    func restartTimeboundSession() async {
        guard let ctx = timerCompletionContext else { return }
        timerCompletionContext = nil
        await startSession(activityId: ctx.activityId, type: .timebound, timerMinutes: ctx.timerMinutes)
    }

    func startBreakSession() async {
        guard let ctx = timerCompletionContext else { return }
        guard case .rhythmFocusExpiry(let breakMins, _) = ctx.completionType else { return }

        // Save context so break-end alert knows what to resume
        breakPrecedingContext = (
            activityId: ctx.activityId,
            title: ctx.activityTitle,
            timerMinutes: ctx.timerMinutes,
            breakMinutes: breakMins
        )
        timerCompletionContext = nil

        do {
            let breakActivity = try await service.getBreakActivity()
            guard let breakId = breakActivity.id else { return }
            await startSession(activityId: breakId, type: .timebound, timerMinutes: breakMins)
        } catch {
            showError(error, context: "Could not start break")
        }
    }

    func startNextFocusSession() async {
        guard let ctx = timerCompletionContext else { return }
        timerCompletionContext = nil

        switch ctx.completionType {
        case .rhythmFocusExpiry:
            // Skip break, restart same focus session
            await startSession(activityId: ctx.activityId, type: .rhythm,
                               timerMinutes: ctx.timerMinutes)
        case .rhythmBreakExpiry(let prevId, _, let prevTimer, let prevBreak):
            // Resume focus after break
            breakPrecedingContext = nil
            await startSession(activityId: prevId, type: .rhythm,
                               timerMinutes: prevTimer, breakMinutes: prevBreak)
        case .timeboundExpiry:
            await startSession(activityId: ctx.activityId, type: .timebound,
                               timerMinutes: ctx.timerMinutes)
        case .timeboundBreakExpiry(let recentId, _, let recentTimer, let recentType):
            guard let recentId else { return }
            await startSession(activityId: recentId, type: recentType ?? .timebound,
                               timerMinutes: recentTimer)
        }
    }

    func endBreakSession() {
        timerCompletionContext = nil
        breakPrecedingContext = nil
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
        ipcServer = IPCServer { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshAll()
            }
        }
        try? ipcServer?.start()
    }

    // MARK: - Error Feedback

    func showError(_ error: Error, context: String? = nil, scene: ErrorScene = .mainWindow) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        presentedError = AppError(
            title: context ?? "Something went wrong",
            message: message,
            scene: scene
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
