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

    // MARK: - Observation & IPC

    private var observationTask: Task<Void, Never>?
    private var midnightTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var ipcServer: IPCServer?

    // MARK: - Callback

    /// Called when a database change or midnight rollover requires a refresh.
    /// AppState sets this to its own `refreshAll()`.
    var onRefreshNeeded: (() async -> Void)?

    // MARK: - Dependencies

    private let service: PresentService
    private let changeNotifier: DatabaseChangeNotifier

    /// Tables whose modifications trigger a data refresh.
    private static let trackedTables = [
        Session.databaseTableName,
        SessionSegment.databaseTableName,
        Activity.databaseTableName,
        ActivityTag.databaseTableName,
        Tag.databaseTableName,
        Preference.databaseTableName,
    ]

    // MARK: - Initialization

    init(service: PresentService, changeNotifier: DatabaseChangeNotifier) {
        self.service = service
        self.changeNotifier = changeNotifier
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

    // MARK: - Database Observation

    /// Starts listening for database changes via `DatabaseRegionObservation`.
    /// Each detected change is debounced (100ms) before triggering a refresh,
    /// so rapid mutations (e.g. stop session = segment + session update)
    /// collapse into a single refresh cycle.
    func startObservations() {
        let stream = changeNotifier.changes(tracking: Self.trackedTables)

        observationTask = Task {
            for await _ in stream {
                guard !Task.isCancelled else { break }
                scheduleRefresh()
            }
        }

        startMidnightTimer()
    }

    // MARK: - Midnight Timer

    /// Schedules a refresh at the next midnight so date-boundary changes
    /// (daily/weekly summaries) update even without database writes.
    private func startMidnightTimer() {
        midnightTask?.cancel()
        midnightTask = Task {
            while !Task.isCancelled {
                let now = Date()
                let calendar = Calendar.current
                guard let nextMidnight = calendar.date(
                    byAdding: .day, value: 1,
                    to: calendar.startOfDay(for: now)
                ) else { break }
                let seconds = nextMidnight.timeIntervalSince(now)
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { break }
                await onRefreshNeeded?()
            }
        }
    }

    // MARK: - Debounce

    /// Schedules a debounced refresh. Multiple calls within 100ms collapse
    /// into a single `onRefreshNeeded` invocation.
    private func scheduleRefresh() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            await onRefreshNeeded?()
        }
    }

    // MARK: - IPC

    func startIPCServer() {
        ipcServer = IPCServer { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh()
            }
        }
        try? ipcServer?.start()
    }
}
