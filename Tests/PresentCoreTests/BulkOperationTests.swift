import Testing
import Foundation
import GRDB
@testable import PresentCore

@Suite("Bulk Operation Tests")
struct BulkOperationTests {

    private func makeService() throws -> (PresentService, any DatabaseWriter) {
        let dbManager = try DatabaseManager(inMemory: true)
        return (PresentService(databasePool: dbManager.writer), dbManager.writer)
    }

    /// Insert a completed session with a specific startedAt date, bypassing the service
    /// which always uses Date() for startedAt.
    private func insertBackdatedSession(db: any DatabaseWriter, activityId: Int64, startedAt: Date) async throws {
        try await db.write { db in
            var session = Session(
                activityId: activityId,
                sessionType: .work,
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(3600),
                durationSeconds: 3600,
                state: .completed,
                createdAt: startedAt
            )
            try session.insert(db)
        }
    }

    // MARK: - countSessions

    @Test func countSessionsTodayReturnsCorrectCount() async throws {
        let (service, db) = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Count Test"))

        _ = try await service.startSession(activityId: activity.id!, type: .work)
        _ = try await service.stopSession()
        _ = try await service.startSession(activityId: activity.id!, type: .work)
        _ = try await service.stopSession()

        let count = try await service.countSessions(in: .today)
        #expect(count == 2)
    }

    @Test func countSessionsEmptyDatabase() async throws {
        let (service, _) = try makeService()
        let count = try await service.countSessions(in: .today)
        #expect(count == 0)
    }

    @Test func countSessionsIncludesActiveSession() async throws {
        let (service, _) = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Active"))

        _ = try await service.startSession(activityId: activity.id!, type: .work)
        // Session is running, not stopped

        let count = try await service.countSessions(in: .today)
        #expect(count == 1)
    }

    // MARK: - deleteSessions

    @Test func deleteSessionsTodayOnlyDeletesTodaySessions() async throws {
        let (service, db) = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Scoped"))

        // Create a session for yesterday by inserting directly
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        try await insertBackdatedSession(db: db, activityId: activity.id!, startedAt: yesterday)

        // Create a session for today via the service
        _ = try await service.startSession(activityId: activity.id!, type: .work)
        _ = try await service.stopSession()

        let result = try await service.deleteSessions(in: .today)
        #expect(result.sessionsDeleted == 1)
        #expect(result.activeSessionCancelled == false)

        // Yesterday's session should still exist
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let remaining = try await service.listSessions(from: twoDaysAgo, to: tomorrow, type: nil, activityId: nil, includeArchived: true)
        #expect(remaining.count == 1)
    }

    @Test func deleteSessionsCancelsActiveSessionInRange() async throws {
        let (service, _) = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Active Cancel"))

        _ = try await service.startSession(activityId: activity.id!, type: .work)
        // Session is running (today)

        let result = try await service.deleteSessions(in: .today)
        #expect(result.activeSessionCancelled == true)
        #expect(result.sessionsDeleted >= 1)

        // No active session should remain
        let current = try await service.currentSession()
        #expect(current == nil)
    }

    @Test func deleteSessionsCancelsPausedSessionInRange() async throws {
        let (service, _) = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Paused Cancel"))

        _ = try await service.startSession(activityId: activity.id!, type: .work)
        _ = try await service.pauseSession()

        let result = try await service.deleteSessions(in: .today)
        #expect(result.activeSessionCancelled == true)

        let current = try await service.currentSession()
        #expect(current == nil)
    }

    @Test func deleteSessionsEmptyDatabase() async throws {
        let (service, _) = try makeService()
        let result = try await service.deleteSessions(in: .today)
        #expect(result.sessionsDeleted == 0)
        #expect(result.activitiesDeleted == 0)
        #expect(result.tagsDeleted == 0)
        #expect(result.activeSessionCancelled == false)
    }

    @Test func deleteSessionsAllTimeDeletesEverything() async throws {
        let (service, db) = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "All Time"))

        // Create a backdated session
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        try await insertBackdatedSession(db: db, activityId: activity.id!, startedAt: lastMonth)

        // Create a today session
        _ = try await service.startSession(activityId: activity.id!, type: .work)
        _ = try await service.stopSession()

        let result = try await service.deleteSessions(in: .allTime)
        #expect(result.sessionsDeleted == 2)
        #expect(result.activeSessionCancelled == false)
    }

    @Test func deleteSessionsDoesNotDeleteActivities() async throws {
        let (service, _) = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Keep Me"))

        _ = try await service.startSession(activityId: activity.id!, type: .work)
        _ = try await service.stopSession()

        _ = try await service.deleteSessions(in: .allTime)

        // Activity should still exist
        let fetched = try await service.getActivity(id: activity.id!)
        #expect(fetched.title == "Keep Me")
    }

    // MARK: - deleteAllActivities

    @Test func deleteAllActivitiesClearsSessionsAndActivities() async throws {
        let (service, _) = try makeService()
        let a1 = try await service.createActivity(CreateActivityInput(title: "Activity 1"))
        let a2 = try await service.createActivity(CreateActivityInput(title: "Activity 2"))

        _ = try await service.startSession(activityId: a1.id!, type: .work)
        _ = try await service.stopSession()
        _ = try await service.startSession(activityId: a2.id!, type: .work)
        _ = try await service.stopSession()

        let result = try await service.deleteAllActivities()
        #expect(result.sessionsDeleted == 2)
        #expect(result.activitiesDeleted == 2)
        #expect(result.activeSessionCancelled == false)

        let activities = try await service.listActivities(includeArchived: true)
        #expect(activities.isEmpty)
    }

    @Test func deleteAllActivitiesCancelsActiveSession() async throws {
        let (service, _) = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Active"))

        _ = try await service.startSession(activityId: activity.id!, type: .work)
        // Session is running

        let result = try await service.deleteAllActivities()
        #expect(result.activeSessionCancelled == true)
        #expect(result.activitiesDeleted == 1)

        let current = try await service.currentSession()
        #expect(current == nil)
    }

    @Test func deleteAllActivitiesEmptyDatabase() async throws {
        let (service, _) = try makeService()
        let result = try await service.deleteAllActivities()
        #expect(result.sessionsDeleted == 0)
        #expect(result.activitiesDeleted == 0)
        #expect(result.tagsDeleted == 0)
        #expect(result.activeSessionCancelled == false)
    }

    @Test func deleteAllActivitiesCascadesActivityTags() async throws {
        let (service, _) = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Tagged"))
        let tag = try await service.createTag(name: "important")
        try await service.tagActivity(activityId: activity.id!, tagId: tag.id!)

        _ = try await service.deleteAllActivities()

        // Tag should still exist (only activity_tag rows cascade from activity deletion)
        let tags = try await service.listTags()
        #expect(tags.count == 1)
        #expect(tags.first?.name == "important")
    }

    // MARK: - deleteAllTags

    @Test func deleteAllTagsRemovesTags() async throws {
        let (service, _) = try makeService()
        _ = try await service.createTag(name: "urgent")
        _ = try await service.createTag(name: "bug")
        _ = try await service.createTag(name: "feature")

        let result = try await service.deleteAllTags()
        #expect(result.tagsDeleted == 3)
        #expect(result.sessionsDeleted == 0)
        #expect(result.activitiesDeleted == 0)

        let tags = try await service.listTags()
        #expect(tags.isEmpty)
    }

    @Test func deleteAllTagsKeepsActivities() async throws {
        let (service, _) = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Keep Me"))
        let tag = try await service.createTag(name: "temp")
        try await service.tagActivity(activityId: activity.id!, tagId: tag.id!)

        _ = try await service.deleteAllTags()

        // Activity should still exist
        let fetched = try await service.getActivity(id: activity.id!)
        #expect(fetched.title == "Keep Me")

        // But its tag associations should be gone (cascaded)
        let tags = try await service.tagsForActivity(activityId: activity.id!)
        #expect(tags.isEmpty)
    }

    @Test func deleteAllTagsEmptyDatabase() async throws {
        let (service, _) = try makeService()
        let result = try await service.deleteAllTags()
        #expect(result.tagsDeleted == 0)
        #expect(result.sessionsDeleted == 0)
        #expect(result.activitiesDeleted == 0)
        #expect(result.activeSessionCancelled == false)
    }

    // MARK: - factoryReset

    @Test func factoryResetWipesEverything() async throws {
        let (service, _) = try makeService()

        // Create activities, tags, sessions, and modify preferences
        let activity = try await service.createActivity(CreateActivityInput(title: "Doomed"))
        let tag = try await service.createTag(name: "doomed-tag")
        try await service.tagActivity(activityId: activity.id!, tagId: tag.id!)
        _ = try await service.startSession(activityId: activity.id!, type: .work)
        _ = try await service.stopSession()
        try await service.setPreference(key: PreferenceKey.defaultRhythmMinutes, value: "50")

        try await service.factoryReset()

        // Everything should be gone
        let activities = try await service.listActivities(includeArchived: true)
        #expect(activities.isEmpty)

        let tags = try await service.listTags()
        #expect(tags.isEmpty)

        let current = try await service.currentSession()
        #expect(current == nil)
    }

    @Test func factoryResetReseedsDefaultPreferences() async throws {
        let (service, _) = try makeService()

        // Change a preference from the default
        try await service.setPreference(key: PreferenceKey.defaultRhythmMinutes, value: "99")

        try await service.factoryReset()

        // Preferences should be back to defaults
        let rhythm = try await service.getPreference(key: PreferenceKey.defaultRhythmMinutes)
        #expect(rhythm == "25")

        let shortBreak = try await service.getPreference(key: PreferenceKey.shortBreakMinutes)
        #expect(shortBreak == "5")

        let longBreak = try await service.getPreference(key: PreferenceKey.longBreakMinutes)
        #expect(longBreak == "15")

        let soundEnabled = try await service.getPreference(key: PreferenceKey.soundEffectsEnabled)
        #expect(soundEnabled == "1")
    }

    @Test func factoryResetCancelsActiveSession() async throws {
        let (service, _) = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Active"))
        _ = try await service.startSession(activityId: activity.id!, type: .work)

        try await service.factoryReset()

        let current = try await service.currentSession()
        #expect(current == nil)
    }

    @Test func factoryResetOnEmptyDatabaseSucceeds() async throws {
        let (service, _) = try makeService()

        // Should not throw on a fresh database
        try await service.factoryReset()

        // Default preferences should still be present
        let rhythm = try await service.getPreference(key: PreferenceKey.defaultRhythmMinutes)
        #expect(rhythm == "25")
    }
}
