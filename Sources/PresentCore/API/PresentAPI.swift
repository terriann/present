import Foundation

public protocol PresentAPI: Sendable {
    // Sessions
    func startSession(activityId: Int64, type: SessionType, timerMinutes: Int?, breakMinutes: Int?) async throws -> Session
    func pauseSession() async throws -> Session
    func resumeSession() async throws -> Session
    func stopSession() async throws -> Session
    func cancelSession() async throws
    func currentSession() async throws -> (Session, Activity)?
    func getSession(id: Int64) async throws -> (Session, Activity)
    func createBackdatedSession(_ input: CreateBackdatedSessionInput) async throws -> Session
    func listSessions(from: Date, to: Date, type: SessionType?, activityId: Int64?, includeArchived: Bool) async throws -> [(Session, Activity)]
    func lastCompletedSession(since: Date) async throws -> (Session, Activity)?
    func lastCompletedNonSystemSession(since: Date) async throws -> (Session, Activity)?
    func earliestSessionDate() async throws -> Date?
    func deleteSession(id: Int64) async throws

    // Activities
    func createActivity(_ input: CreateActivityInput) async throws -> Activity
    func updateActivity(id: Int64, _ input: UpdateActivityInput) async throws -> Activity
    func archiveActivity(id: Int64) async throws -> ArchiveResult
    func deleteActivity(id: Int64) async throws
    func unarchiveActivity(id: Int64) async throws -> Activity
    func listActivities(includeArchived: Bool, includeSystem: Bool) async throws -> [Activity]
    func getActivity(id: Int64) async throws -> Activity
    func searchActivities(query: String) async throws -> [Activity]
    func recentActivities(limit: Int) async throws -> [Activity]
    func getBreakActivity() async throws -> Activity

    // Notes
    func appendNote(activityId: Int64, text: String) async throws -> Activity

    // Tags
    func createTag(name: String) async throws -> Tag
    func getTag(id: Int64) async throws -> Tag
    func updateTag(id: Int64, name: String) async throws -> Tag
    func deleteTag(id: Int64) async throws
    func listTags() async throws -> [Tag]
    func tagActivity(activityId: Int64, tagId: Int64) async throws
    func untagActivity(activityId: Int64, tagId: Int64) async throws
    func setActivityTags(activityId: Int64, tagIds: [Int64]) async throws -> [Tag]
    func tagsForActivity(activityId: Int64) async throws -> [Tag]
    func tagsForActivities(activityIds: [Int64]) async throws -> [Int64: [Tag]]

    // Reports
    func activitySummary(from: Date, to: Date, includeArchived: Bool) async throws -> [ActivitySummary]
    func dailySummary(date: Date, includeArchived: Bool, roundToMinute: Bool) async throws -> DailySummary
    func weeklySummary(weekOf: Date, includeArchived: Bool, weekStartDay: Int, roundToMinute: Bool) async throws -> WeeklySummary
    func monthlySummary(monthOf: Date, includeArchived: Bool, weekStartDay: Int, roundToMinute: Bool) async throws -> MonthlySummary
    func tagSummary(from: Date, to: Date, includeArchived: Bool) async throws -> [TagSummary]
    func tagActivitySummary(from: Date, to: Date, includeArchived: Bool) async throws -> [TagActivitySummary]
    func exportCSV(from: Date, to: Date, includeArchived: Bool) async throws -> Data

    // Preferences
    func getPreference(key: String) async throws -> String?
    func setPreference(key: String, value: String) async throws
    func listPreferences() async throws -> [(key: String, value: String)]

    // Segments
    func sessionDayPortions(sessionIds: [Int64], date: Date) async throws -> [Int64: Int]

    // Status
    func todaySummary() async throws -> TodaySummary

    // Bulk Operations
    func countSessions(in range: BulkDeleteRange) async throws -> Int
    func deleteSessions(in range: BulkDeleteRange) async throws -> BulkDeleteResult
    func deleteAllActivities() async throws -> BulkDeleteResult
    func deleteAllTags() async throws -> BulkDeleteResult
    func factoryReset() async throws
}

// MARK: - Default Parameters

public extension PresentAPI {
    func listActivities(includeArchived: Bool) async throws -> [Activity] {
        try await listActivities(includeArchived: includeArchived, includeSystem: false)
    }

    func dailySummary(date: Date, includeArchived: Bool) async throws -> DailySummary {
        try await dailySummary(date: date, includeArchived: includeArchived, roundToMinute: false)
    }

    func weeklySummary(weekOf: Date, includeArchived: Bool, weekStartDay: Int) async throws -> WeeklySummary {
        try await weeklySummary(weekOf: weekOf, includeArchived: includeArchived, weekStartDay: weekStartDay, roundToMinute: false)
    }

    func monthlySummary(monthOf: Date, includeArchived: Bool, weekStartDay: Int) async throws -> MonthlySummary {
        try await monthlySummary(monthOf: monthOf, includeArchived: includeArchived, weekStartDay: weekStartDay, roundToMinute: false)
    }
}
