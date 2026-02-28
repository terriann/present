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
    var popoverActivities: [Activity] = []
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
    /// All assignments are guarded by equality checks to avoid unnecessary SwiftUI diffs.
    func refreshData(hasActiveSession: Bool) async throws {
        let summary = try await service.todaySummary()
        if todayTotalSeconds != summary.totalSeconds { todayTotalSeconds = summary.totalSeconds }
        if todaySessionCount != summary.sessionCount { todaySessionCount = summary.sessionCount }
        if todayActivities != summary.activities { todayActivities = summary.activities }

        if let weekStartPref = try? await service.getPreference(key: PreferenceKey.weekStartDay) {
            let parsed = PreferenceKey.parseWeekStartDay(weekStartPref)
            if weekStartDay != parsed { weekStartDay = parsed }
        }
        let weekly = try await service.weeklySummary(weekOf: Date(), includeArchived: false, weekStartDay: weekStartDay, roundToMinute: true)
        if weekly != weeklySummary { weeklySummary = weekly }

        if !hasActiveSession {
            let since = Date().addingTimeInterval(-3 * 60 * 60)
            let suggestion = try await service.lastCompletedSession(since: since)
            if !suggestionEquals(recentSessionSuggestion, suggestion) {
                recentSessionSuggestion = suggestion
            }
        } else if recentSessionSuggestion != nil {
            recentSessionSuggestion = nil
        }

        let newRecent = try await service.recentActivities(limit: 6)
        if recentActivities != newRecent { recentActivities = newRecent }

        let newPopover = try await service.listActivitiesForPopover()
        if popoverActivities != newPopover { popoverActivities = newPopover }

        let newAll = try await service.listActivities(includeArchived: true, includeSystem: true)
        if allActivities != newAll { allActivities = newAll }

        let newTags = try await service.listTags()
        if allTags != newTags { allTags = newTags }

        if let optionsStr = try? await service.getPreference(key: PreferenceKey.rhythmDurationOptions) {
            let parsed: [RhythmOption] = PreferenceKey.parseRhythmOptions(optionsStr)
            let newOptions = parsed.isEmpty ? Constants.defaultRhythmDurationOptions : parsed
            if rhythmDurationOptions != newOptions { rhythmDurationOptions = newOptions }
        }
    }

    /// Compare optional session suggestion tuples (tuples don't auto-conform to Equatable).
    private func suggestionEquals(
        _ lhs: (session: Session, activity: Activity)?,
        _ rhs: (session: Session, activity: Activity)?
    ) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): return true
        case let (.some(l), .some(r)): return l.session == r.session && l.activity == r.activity
        default: return false
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
        ipcServer = IPCServer { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.onRefreshNeeded?()
            }
        }
        try? ipcServer?.start()
    }
}
