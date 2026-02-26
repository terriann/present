import SwiftUI
import PresentCore

@MainActor @Observable
final class DataRefreshCoordinator {
    // MARK: - Data State

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

    // MARK: - Polling & IPC

    private var observationTask: Task<Void, Never>?
    private var ipcServer: IPCServer?

    // MARK: - Callback

    /// Called from the polling loop when a refresh cycle is due.
    /// AppState sets this to its own `refreshAll()`.
    var onRefreshNeeded: (() async -> Void)?

    // MARK: - Dependencies

    private let service: PresentService

    // MARK: - Initialization

    init(service: PresentService) {
        self.service = service
    }

    // MARK: - Data Refresh

    /// Refreshes data-only properties. Session/timer sync is handled by AppState.
    func refreshData(hasActiveSession: Bool) async throws {
        let summary = try await service.todaySummary()
        todayTotalSeconds = summary.totalSeconds
        todaySessionCount = summary.sessionCount
        todayActivities = summary.activities

        if let weekStartPref = try? await service.getPreference(key: PreferenceKey.weekStartDay) {
            weekStartDay = PreferenceKey.parseWeekStartDay(weekStartPref)
        }
        let weekly = try await service.weeklySummary(weekOf: Date(), includeArchived: false, weekStartDay: weekStartDay, roundToMinute: true)
        if weekly != weeklySummary { weeklySummary = weekly }

        if !hasActiveSession {
            let since = Date().addingTimeInterval(-3 * 60 * 60)
            recentSessionSuggestion = try await service.lastCompletedSession(since: since)
        } else {
            recentSessionSuggestion = nil
        }

        recentActivities = try await service.recentActivities(limit: 6)
        allActivities = try await service.listActivities(includeArchived: true, includeSystem: true)
        allTags = try await service.listTags()

        if let optionsStr = try? await service.getPreference(key: PreferenceKey.rhythmDurationOptions) {
            let parsed: [RhythmOption] = PreferenceKey.parseRhythmOptions(optionsStr)
            rhythmDurationOptions = parsed.isEmpty ? Constants.defaultRhythmDurationOptions : parsed
        }
    }

    // MARK: - Polling

    func startObservations() {
        observationTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                await onRefreshNeeded?()
            }
        }
    }

    // MARK: - IPC

    func startIPCServer() {
        ipcServer = IPCServer { _ in
            Task { @MainActor in
                // Refresh handled by periodic polling
            }
        }
        try? ipcServer?.start()
    }
}
