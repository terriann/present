import SwiftUI
import PresentCore

@MainActor @Observable
final class AppState {
    // MARK: - Session State

    var currentSession: Session?
    var currentActivity: Activity?

    // MARK: - Data (forwarded from DataRefreshCoordinator)

    private(set) var dataRefresh: DataRefreshCoordinator!

    var todayTotalSeconds: Int { dataRefresh.todayTotalSeconds }
    var todaySessionCount: Int { dataRefresh.todaySessionCount }
    var todayActivities: [ActivitySummary] { dataRefresh.todayActivities }
    var weeklySummary: WeeklySummary? { dataRefresh.weeklySummary }
    var weekStartDay: Int { dataRefresh.weekStartDay }
    var recentActivities: [Activity] { dataRefresh.recentActivities }
    var popoverActivities: [Activity] { dataRefresh.popoverActivities }
    var allTags: [Tag] { dataRefresh.allTags }
    var recentSessionSuggestion: (session: Session, activity: Activity)? { dataRefresh.recentSessionSuggestion }
    var rhythmDurationOptions: [RhythmOption] { dataRefresh.rhythmDurationOptions }
    var refreshCounter: Int { dataRefresh.refreshCounter }

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
    var pendingNavigation: NavigationAction?
    var pendingSettingsTab: SettingsTab?

    /// Centralized navigation entry point.
    ///
    /// Sets the relevant sidebar/activity state and queues a `pendingNavigation`
    /// action that `MenuBarLabelView` consumes via `onChange` to open windows.
    func navigate(to action: NavigationAction) {
        switch action {
        case .launchMainWindow:
            pendingNavigation = .launchMainWindow

        case .showDashboard:
            selectedSidebarItem = .dashboard
            pendingNavigation = .launchMainWindow

        case .showActivity(let id):
            navigateToActivityId = id
            selectedSidebarItem = .activities
            pendingNavigation = .launchMainWindow

        case .showSettings(let tab):
            if let tab {
                pendingSettingsTab = tab
            }
            pendingNavigation = .showSettings(tab)
        }
    }

    // MARK: - Session (delegated to SessionManager)

    private(set) var sessionMgr: SessionManager!

    // MARK: - Services

    private var service: any PresentAPI
    private let dbManager: DatabaseManager

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
            Self.showDatabaseErrorAndTerminate(error)
        }
        service = PresentService(databasePool: dbManager.writer)
        zoom = ZoomManager(service: service)
        timer = TimerManager(service: service)
        timer.onCountdownCompleted = { [weak self] in
            await self?.handleTimerCompletion()
        }
        sessionMgr = SessionManager(service: service)
        let changeNotifier = DatabaseChangeNotifier(writer: dbManager.writer)
        dataRefresh = DataRefreshCoordinator(service: service, changeNotifier: changeNotifier)
        dataRefresh.onRefreshNeeded = { [weak self] in
            await self?.refreshAll()
        }
        NotificationManager.shared.requestPermission()
        Task {
            let val = try? await service.getPreference(key: PreferenceKey.soundEffectsEnabled)
            SoundManager.shared.configure(soundEnabled: val != "0")
        }
        dataRefresh.startObservations()
        dataRefresh.startIPCServer()
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
            // 1. Sync session state
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

            // 2. Refresh data properties
            try await dataRefresh.refreshData(hasActiveSession: currentSession != nil)

            // 3. Refresh preferences
            await zoom.loadFromPreferences()
        } catch {
            print("Error refreshing data: \(error)")
        }
    }

    // MARK: - Session Actions

    func startSession(activityId: Int64, type: SessionType, timerMinutes: Int? = nil, breakMinutes: Int? = nil) async {
        timer.clearCompletedTimerLinger()
        timerCompletionContext = nil
        do {
            let (session, activity) = try await sessionMgr.startSession(
                activityId: activityId,
                type: type,
                timerMinutes: timerMinutes,
                breakMinutes: breakMinutes
            )
            currentSession = session
            currentActivity = activity
            timer.startTimer(session: session)
            SoundManager.shared.play(.blow)
            await refreshAll()
        } catch {
            showError(error, context: "Could not start session")
        }
    }

    func pauseSession() async {
        do {
            let session = try await sessionMgr.pauseSession()
            currentSession = session
            timer.currentSession = session
            timer.stopTimer(resetElapsed: false)
        } catch {
            showError(error, context: "Could not pause session")
        }
    }

    func resumeSession() async {
        do {
            let session = try await sessionMgr.resumeSession()
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
            _ = try await sessionMgr.stopSession()
            currentSession = nil
            currentActivity = nil
            timer.currentSession = nil
            timer.stopTimer()

            // Play completion sound and start linger unless handleTimerCompletion already did
            if completedTimerText == nil {
                SoundManager.shared.play(.shimmer)
                timer.startCompletedTimerLinger(text: finalText, isCountdown: false)
            }

            await refreshAll()
        } catch {
            showError(error, context: "Could not stop session")
        }
    }

    func switchSession(to activityId: Int64, type: SessionType, timerMinutes: Int? = nil, breakMinutes: Int? = nil) async {
        timer.clearCompletedTimerLinger()
        timerCompletionContext = nil
        do {
            let result = try await sessionMgr.switchSession(
                to: activityId,
                type: type,
                timerMinutes: timerMinutes,
                breakMinutes: breakMinutes
            )
            currentSession = result.started
            currentActivity = result.activity
            timer.startTimer(session: result.started)
            SoundManager.shared.play(.blow)
            await refreshAll()
        } catch {
            showError(error, context: "Could not switch session")
        }
    }

    func cancelSession() async {
        do {
            try await sessionMgr.cancelSession()
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

    func updateSession(id: Int64, _ input: UpdateSessionInput) async throws {
        let updated = try await sessionMgr.updateSession(id: id, input)
        if updated.id == currentSession?.id {
            currentSession = updated
        }
        await refreshAll()
    }

    func convertSession(_ input: ConvertSessionInput) async {
        do {
            // If converting away from rhythm, abandon the rhythm cycle
            if currentSession?.sessionType == .rhythm, input.targetType != .rhythm {
                breakPrecedingContext = nil
            }
            let session = try await sessionMgr.convertSessionType(input)
            currentSession = session
            timer.currentSession = session
            timer.resetCompletionHandled()
            IPCClient().send(.sessionConverted)
            await refreshAll()
        } catch {
            showError(error, context: "Could not convert session")
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
            let breakActivity = try await sessionMgr.getBreakActivity()
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

    // MARK: - Error Feedback

    func showError(_ error: Error, context: String? = nil, scene: ErrorScene = .mainWindow) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        presentedError = AppError(
            title: context ?? "Something went wrong",
            message: message,
            scene: scene
        )
    }

    // MARK: - Preferences

    func getPreference(key: String) async throws -> String? {
        try await service.getPreference(key: key)
    }

    func setPreference(key: String, value: String) async throws {
        try await service.setPreference(key: key, value: value)
    }

    /// Returns the user's preferred timebound duration, falling back to the default.
    func loadDefaultTimeboundMinutes() async -> Int {
        (try? await getPreference(key: PreferenceKey.defaultTimeboundMinutes))
            .flatMap(Int.init) ?? Constants.defaultTimeboundMinutes
    }

    // MARK: - Activities

    func getActivity(id: Int64) async throws -> Activity {
        try await service.getActivity(id: id)
    }

    func listActivities(includeArchived: Bool = false, includeSystem: Bool = false) async throws -> [Activity] {
        try await service.listActivities(includeArchived: includeArchived, includeSystem: includeSystem)
    }

    func createActivity(_ input: CreateActivityInput) async throws -> Activity {
        try await service.createActivity(input)
    }

    func updateActivity(id: Int64, _ input: UpdateActivityInput) async throws -> Activity {
        try await service.updateActivity(id: id, input)
    }

    func archiveActivity(id: Int64, force: Bool = false) async throws -> ArchiveResult {
        try await service.archiveActivity(id: id, force: force)
    }

    func unarchiveActivity(id: Int64) async throws -> Activity {
        try await service.unarchiveActivity(id: id)
    }

    func deleteActivity(id: Int64) async throws {
        try await service.deleteActivity(id: id)
    }

    // MARK: - Tags

    func findOrCreateTag(name: String) async throws -> Tag {
        try await service.findOrCreateTag(name: name)
    }

    func tagActivity(activityId: Int64, tagId: Int64) async throws {
        try await service.tagActivity(activityId: activityId, tagId: tagId)
    }

    func untagActivity(activityId: Int64, tagId: Int64) async throws {
        try await service.untagActivity(activityId: activityId, tagId: tagId)
    }

    func tagsForActivity(activityId: Int64) async throws -> [Tag] {
        try await service.tagsForActivity(activityId: activityId)
    }

    func tagsForActivities(activityIds: [Int64]) async throws -> [Int64: [Tag]] {
        try await service.tagsForActivities(activityIds: activityIds)
    }

    // MARK: - Sessions (Query)

    func deleteSession(id: Int64) async throws {
        try await service.deleteSession(id: id)
    }

    func listSessions(from: Date, to: Date, type: SessionType? = nil, activityId: Int64? = nil, includeArchived: Bool = false) async throws -> [(Session, Activity)] {
        try await service.listSessions(from: from, to: to, type: type, activityId: activityId, includeArchived: includeArchived)
    }

    func datesWithSessions(from: Date, to: Date) async throws -> Set<Date> {
        try await service.datesWithSessions(from: from, to: to)
    }

    func monthsWithSessions(from: Date, to: Date) async throws -> Set<String> {
        try await service.monthsWithSessions(from: from, to: to)
    }

    func segmentsForSessions(sessionIds: [Int64]) async throws -> [Int64: [SessionSegment]] {
        try await service.segmentsForSessions(sessionIds: sessionIds)
    }

    func sessionDayPortions(sessionIds: [Int64], date: Date) async throws -> [Int64: Int] {
        try await service.sessionDayPortions(sessionIds: sessionIds, date: date)
    }

    // MARK: - Reports

    func dailySummary(date: Date, includeArchived: Bool, roundToMinute: Bool) async throws -> DailySummary {
        try await service.dailySummary(date: date, includeArchived: includeArchived, roundToMinute: roundToMinute)
    }

    func weeklySummary(weekOf: Date, includeArchived: Bool, weekStartDay: Int = 1, roundToMinute: Bool = false) async throws -> WeeklySummary {
        try await service.weeklySummary(weekOf: weekOf, includeArchived: includeArchived, weekStartDay: weekStartDay, roundToMinute: roundToMinute)
    }

    func monthlySummary(monthOf: Date, includeArchived: Bool, weekStartDay: Int = 1, roundToMinute: Bool = false) async throws -> MonthlySummary {
        try await service.monthlySummary(monthOf: monthOf, includeArchived: includeArchived, weekStartDay: weekStartDay, roundToMinute: roundToMinute)
    }

    func tagActivitySummary(from: Date, to: Date, includeArchived: Bool, roundToMinute: Bool) async throws -> [TagActivitySummary] {
        try await service.tagActivitySummary(from: from, to: to, includeArchived: includeArchived, roundToMinute: roundToMinute)
    }

    func earliestSessionDate() async throws -> Date? {
        try await service.earliestSessionDate()
    }

    // MARK: - Bulk Operations

    func countSessions(in range: BulkDeleteRange) async throws -> Int {
        try await service.countSessions(in: range)
    }

    func deleteSessions(in range: BulkDeleteRange) async throws -> BulkDeleteResult {
        try await service.deleteSessions(in: range)
    }

    // MARK: - Dock Icon

    func showDockIcon(_ show: Bool) {
        if show {
            NSApplication.shared.setActivationPolicy(.regular)
        } else {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Database Recovery

    /// Shows a modal alert describing the database error and offers to reset or quit.
    /// This is called during init when DatabaseManager fails, before any UI is rendered.
    private static func showDatabaseErrorAndTerminate(_ error: Error) -> Never {
        let alert = NSAlert()
        alert.messageText = "Present could not open its data"
        alert.informativeText = """
            The database failed to initialize. This may be caused by a corrupt file or a permissions issue.

            You can reset the database to start fresh (all existing data will be lost), or quit and investigate manually.

            Error: \(error.localizedDescription)
            Location: \(DatabaseManager.defaultDatabasePath)
            """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Reset and Relaunch")
        alert.addButton(withTitle: "Reveal in Finder")
        alert.addButton(withTitle: "Quit Present")

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // Reset: remove database files and relaunch
            let path = DatabaseManager.defaultDatabasePath
            let fm = FileManager.default
            for suffix in ["", "-wal", "-shm"] {
                try? fm.removeItem(atPath: path + suffix)
            }
            // Relaunch the app
            let url = Bundle.main.bundleURL
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = [url.path]
            try? task.run()
            exit(0)

        case .alertSecondButtonReturn:
            // Reveal in Finder, then show the alert again
            let dbURL = URL(fileURLWithPath: DatabaseManager.defaultDatabasePath).deletingLastPathComponent()
            NSWorkspace.shared.open(dbURL)
            // Re-show the alert so they can still choose reset or quit
            Self.showDatabaseErrorAndTerminate(error)

        default:
            // Quit
            exit(1)
        }
    }
}
