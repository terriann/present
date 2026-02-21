import Testing
import Foundation
import GRDB
@testable import PresentCore

@Suite("PresentService Tests")
struct PresentServiceTests {

    private func makeService() throws -> PresentService {
        let dbManager = try DatabaseManager(inMemory: true)
        return PresentService(databasePool: dbManager.writer)
    }

    // MARK: - Activity CRUD

    @Test func createActivity() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Test Activity"))
        #expect(activity.id != nil)
        #expect(activity.title == "Test Activity")
        #expect(activity.isArchived == false)
    }

    @Test func createActivityEmptyTitleFails() async throws {
        let service = try makeService()
        await #expect(throws: PresentError.self) {
            try await service.createActivity(CreateActivityInput(title: "   "))
        }
    }

    @Test func createActivityLimit() async throws {
        let service = try makeService()
        for i in 1...50 {
            _ = try await service.createActivity(CreateActivityInput(title: "Activity \(i)"))
        }
        await #expect(throws: PresentError.self) {
            try await service.createActivity(CreateActivityInput(title: "Activity 51"))
        }
    }

    @Test func updateActivity() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Original"))
        let updated = try await service.updateActivity(id: activity.id!, UpdateActivityInput(title: "Updated"))
        #expect(updated.title == "Updated")
    }

    @Test func getActivity() async throws {
        let service = try makeService()
        let created = try await service.createActivity(CreateActivityInput(title: "Get Me"))
        let fetched = try await service.getActivity(id: created.id!)
        #expect(fetched.title == "Get Me")
    }

    @Test func listActivities() async throws {
        let service = try makeService()
        _ = try await service.createActivity(CreateActivityInput(title: "Active"))
        _ = try await service.createActivity(CreateActivityInput(title: "Also Active"))

        let active = try await service.listActivities(includeArchived: false)
        #expect(active.count == 2)
    }

    @Test func deleteActivity() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Delete Me"))
        try await service.deleteActivity(id: activity.id!)

        await #expect(throws: PresentError.self) {
            try await service.getActivity(id: activity.id!)
        }
    }

    @Test func archivePromptDelete() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Quick Task"))
        let result = try await service.archiveActivity(id: activity.id!)
        guard case .promptDelete = result else {
            Issue.record("Expected promptDelete but got \(result)")
            return
        }
    }

    // MARK: - Session Lifecycle

    @Test func startStopWorkSession() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Work"))
        let session = try await service.startSession(activityId: activity.id!, type: .work)
        #expect(session.state == .running)
        #expect(session.sessionType == .work)

        let stopped = try await service.stopSession()
        #expect(stopped.state == .completed)
        #expect(stopped.durationSeconds != nil)
        #expect(stopped.durationSeconds! >= 0)
    }

    @Test func cannotStartDuplicateSession() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Work"))
        _ = try await service.startSession(activityId: activity.id!, type: .work)

        await #expect(throws: PresentError.self) {
            try await service.startSession(activityId: activity.id!, type: .work)
        }
    }

    @Test func pauseResumeSession() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Work"))
        _ = try await service.startSession(activityId: activity.id!, type: .work)

        let paused = try await service.pauseSession()
        #expect(paused.state == .paused)
        #expect(paused.lastPausedAt != nil)

        let resumed = try await service.resumeSession()
        #expect(resumed.state == .running)
        #expect(resumed.lastPausedAt == nil)
        #expect(resumed.totalPausedSeconds >= 0)
    }

    @Test func stopPausedSession() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Work"))
        _ = try await service.startSession(activityId: activity.id!, type: .work)
        _ = try await service.pauseSession()

        let stopped = try await service.stopSession()
        #expect(stopped.state == .completed)
        #expect(stopped.totalPausedSeconds >= 0)
    }

    @Test func cancelSession() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Work"))
        _ = try await service.startSession(activityId: activity.id!, type: .work)

        try await service.cancelSession()
        let current = try await service.currentSession()
        #expect(current == nil)
    }

    @Test func currentSessionNone() async throws {
        let service = try makeService()
        let current = try await service.currentSession()
        #expect(current == nil)
    }

    @Test func rhythmSessionIndex() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Focus"))

        let s1 = try await service.startSession(activityId: activity.id!, type: .rhythm, timerMinutes: 25)
        #expect(s1.rhythmSessionIndex == 1)
        _ = try await service.stopSession()

        let s2 = try await service.startSession(activityId: activity.id!, type: .rhythm, timerMinutes: 25)
        #expect(s2.rhythmSessionIndex == 2)
        _ = try await service.stopSession()

        let s3 = try await service.startSession(activityId: activity.id!, type: .rhythm, timerMinutes: 25)
        #expect(s3.rhythmSessionIndex == 3)
        _ = try await service.stopSession()

        let s4 = try await service.startSession(activityId: activity.id!, type: .rhythm, timerMinutes: 25)
        #expect(s4.rhythmSessionIndex == 4)
        _ = try await service.stopSession()

        // Cycle resets
        let s5 = try await service.startSession(activityId: activity.id!, type: .rhythm, timerMinutes: 25)
        #expect(s5.rhythmSessionIndex == 1)
        _ = try await service.stopSession()
    }

    @Test func timeboundSession() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Timed"))
        let session = try await service.startSession(activityId: activity.id!, type: .timebound, timerMinutes: 15)
        #expect(session.timerLengthMinutes == 15)
        #expect(session.sessionType == .timebound)
        _ = try await service.stopSession()
    }

    // MARK: - Notes

    @Test func appendNote() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Note Test"))
        let updated = try await service.appendNote(activityId: activity.id!, text: "First note")
        #expect(updated.notes == "First note")

        let updated2 = try await service.appendNote(activityId: activity.id!, text: "Second note")
        #expect(updated2.notes == "First note\nSecond note")
    }

    // MARK: - Tags

    @Test func createListTags() async throws {
        let service = try makeService()
        _ = try await service.createTag(name: "urgent")
        _ = try await service.createTag(name: "bug")

        let tags = try await service.listTags()
        #expect(tags.count == 2)
    }

    @Test func tagActivity() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Tagged"))
        let tag = try await service.createTag(name: "important")

        try await service.tagActivity(activityId: activity.id!, tagId: tag.id!)
        try await service.untagActivity(activityId: activity.id!, tagId: tag.id!)
    }

    @Test func deleteTag() async throws {
        let service = try makeService()
        let tag = try await service.createTag(name: "temp")
        try await service.deleteTag(id: tag.id!)

        let tags = try await service.listTags()
        #expect(tags.count == 0)
    }

    // MARK: - Preferences

    @Test func preferences() async throws {
        let service = try makeService()
        let defaultRhythm = try await service.getPreference(key: PreferenceKey.defaultRhythmMinutes)
        #expect(defaultRhythm == "25")

        try await service.setPreference(key: PreferenceKey.defaultRhythmMinutes, value: "30")
        let updated = try await service.getPreference(key: PreferenceKey.defaultRhythmMinutes)
        #expect(updated == "30")
    }

    // MARK: - Reports

    @Test func dailySummary() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Report Test"))
        _ = try await service.startSession(activityId: activity.id!, type: .work)
        _ = try await service.stopSession()

        let summary = try await service.dailySummary(date: Date(), includeArchived: false)
        #expect(summary.sessionCount == 1)
        #expect(summary.activities.count == 1)
        #expect(summary.activities.first?.activity.title == "Report Test")
    }

    @Test func todaySummary() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Today Test"))
        _ = try await service.startSession(activityId: activity.id!, type: .work)
        _ = try await service.stopSession()

        let summary = try await service.todaySummary()
        #expect(summary.sessionCount == 1)
    }

    @Test func csvExport() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "CSV Test"))
        _ = try await service.startSession(activityId: activity.id!, type: .work)
        _ = try await service.stopSession()

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let data = try await service.exportCSV(from: yesterday, to: tomorrow, includeArchived: false)
        let csv = String(data: data, encoding: .utf8)!
        #expect(csv.contains("CSV Test"))
        #expect(csv.contains("Session ID"))
    }

    // MARK: - List Sessions (Filtered)

    @Test func listSessionsDateRange() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Filtered"))
        _ = try await service.startSession(activityId: activity.id!, type: .work)
        _ = try await service.stopSession()

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!

        let sessions = try await service.listSessions(from: yesterday, to: tomorrow, type: nil, activityId: nil, includeArchived: true)
        #expect(sessions.count == 1)
        #expect(sessions.first?.1.title == "Filtered")
    }

    @Test func listSessionsFilterByType() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Multi"))
        _ = try await service.startSession(activityId: activity.id!, type: .work)
        _ = try await service.stopSession()
        _ = try await service.startSession(activityId: activity.id!, type: .rhythm, timerMinutes: 25)
        _ = try await service.stopSession()

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!

        let workOnly = try await service.listSessions(from: yesterday, to: tomorrow, type: .work, activityId: nil, includeArchived: true)
        #expect(workOnly.count == 1)

        let rhythmOnly = try await service.listSessions(from: yesterday, to: tomorrow, type: .rhythm, activityId: nil, includeArchived: true)
        #expect(rhythmOnly.count == 1)

        let all = try await service.listSessions(from: yesterday, to: tomorrow, type: nil, activityId: nil, includeArchived: true)
        #expect(all.count == 2)
    }

    @Test func listSessionsFilterByActivity() async throws {
        let service = try makeService()
        let a1 = try await service.createActivity(CreateActivityInput(title: "A1"))
        let a2 = try await service.createActivity(CreateActivityInput(title: "A2"))
        _ = try await service.startSession(activityId: a1.id!, type: .work)
        _ = try await service.stopSession()
        _ = try await service.startSession(activityId: a2.id!, type: .work)
        _ = try await service.stopSession()

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!

        let a1Sessions = try await service.listSessions(from: yesterday, to: tomorrow, type: nil, activityId: a1.id, includeArchived: true)
        #expect(a1Sessions.count == 1)
        #expect(a1Sessions.first?.1.title == "A1")
    }

    // MARK: - Tags for Activity

    @Test func tagsForActivity() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Tagged"))
        let tag1 = try await service.createTag(name: "frontend")
        let tag2 = try await service.createTag(name: "backend")
        _ = try await service.createTag(name: "unrelated")

        try await service.tagActivity(activityId: activity.id!, tagId: tag1.id!)
        try await service.tagActivity(activityId: activity.id!, tagId: tag2.id!)

        let tags = try await service.tagsForActivity(activityId: activity.id!)
        #expect(tags.count == 2)
        let names = tags.map(\.name).sorted()
        #expect(names == ["backend", "frontend"])
    }

    @Test func tagsForActivityEmpty() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "No Tags"))
        let tags = try await service.tagsForActivity(activityId: activity.id!)
        #expect(tags.isEmpty)
    }

    // MARK: - Search Activities

    @Test func searchActivities() async throws {
        let service = try makeService()
        _ = try await service.createActivity(CreateActivityInput(title: "Design Homepage"))
        _ = try await service.createActivity(CreateActivityInput(title: "Backend API"))
        _ = try await service.createActivity(CreateActivityInput(title: "Design System"))

        let results = try await service.searchActivities(query: "design")
        #expect(results.count == 2)
    }

    @Test func searchActivitiesEmptyQuery() async throws {
        let service = try makeService()
        _ = try await service.createActivity(CreateActivityInput(title: "Something"))
        let results = try await service.searchActivities(query: "  ")
        #expect(results.isEmpty)
    }

    // MARK: - Input Validation

    @Test func activityTitleTooLong() async throws {
        let service = try makeService()
        let longTitle = String(repeating: "a", count: Constants.maxTitleLength + 1)
        await #expect(throws: PresentError.self) {
            try await service.createActivity(CreateActivityInput(title: longTitle))
        }
    }

    @Test func activityTitleMaxLengthSucceeds() async throws {
        let service = try makeService()
        let title = String(repeating: "a", count: Constants.maxTitleLength)
        let activity = try await service.createActivity(CreateActivityInput(title: title))
        #expect(activity.title.count == Constants.maxTitleLength)
    }

    @Test func activityTitleTrimsWhitespace() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "  Hello World  "))
        #expect(activity.title == "Hello World")
    }

    @Test func activityTitleRejectsControlChars() async throws {
        let service = try makeService()
        await #expect(throws: PresentError.self) {
            try await service.createActivity(CreateActivityInput(title: "Bad\u{0000}Title"))
        }
    }

    @Test func activityInvalidLinkFails() async throws {
        let service = try makeService()
        await #expect(throws: PresentError.self) {
            try await service.createActivity(CreateActivityInput(title: "Test", link: "not-a-url"))
        }
    }

    @Test func activityValidLinkSucceeds() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Test", link: "https://example.com"))
        #expect(activity.link == "https://example.com")
    }

    @Test func activityExternalIdTooLong() async throws {
        let service = try makeService()
        let longId = String(repeating: "x", count: Constants.maxExternalIdLength + 1)
        await #expect(throws: PresentError.self) {
            try await service.createActivity(CreateActivityInput(title: "Test", externalId: longId))
        }
    }

    @Test func updateActivityTitleTooLong() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Original"))
        let longTitle = String(repeating: "a", count: Constants.maxTitleLength + 1)
        await #expect(throws: PresentError.self) {
            try await service.updateActivity(id: activity.id!, UpdateActivityInput(title: longTitle))
        }
    }

    @Test func updateActivityInvalidLink() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Original"))
        await #expect(throws: PresentError.self) {
            try await service.updateActivity(id: activity.id!, UpdateActivityInput(link: "bad-link"))
        }
    }

    @Test func tagNameTooLong() async throws {
        let service = try makeService()
        let longName = String(repeating: "t", count: Constants.maxTagNameLength + 1)
        await #expect(throws: PresentError.self) {
            try await service.createTag(name: longName)
        }
    }

    @Test func tagNameCaseInsensitiveUnique() async throws {
        let service = try makeService()
        _ = try await service.createTag(name: "Work")
        await #expect(throws: PresentError.self) {
            try await service.createTag(name: "work")
        }
    }

    @Test func tagNameCaseInsensitiveUniquePreservesOriginal() async throws {
        let service = try makeService()
        let tag = try await service.createTag(name: "Work")
        #expect(tag.name == "Work")

        // Different casing should fail
        await #expect(throws: PresentError.self) {
            try await service.createTag(name: "WORK")
        }
    }

    @Test func updateTagNameCaseInsensitiveUnique() async throws {
        let service = try makeService()
        _ = try await service.createTag(name: "frontend")
        let tag2 = try await service.createTag(name: "backend")
        await #expect(throws: PresentError.self) {
            try await service.updateTag(id: tag2.id!, name: "Frontend")
        }
    }

    @Test func updateTagCanKeepOwnName() async throws {
        let service = try makeService()
        let tag = try await service.createTag(name: "frontend")
        // Updating to same name (different case) should succeed
        let updated = try await service.updateTag(id: tag.id!, name: "Frontend")
        #expect(updated.name == "Frontend")
    }

    @Test func appendNoteTooLong() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Notes Test"))
        let longNote = String(repeating: "n", count: Constants.maxNotesLength + 1)
        await #expect(throws: PresentError.self) {
            try await service.appendNote(activityId: activity.id!, text: longNote)
        }
    }

    @Test func sessionTimerMinutesOutOfRange() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Timer Test"))
        await #expect(throws: PresentError.self) {
            try await service.startSession(activityId: activity.id!, type: .timebound, timerMinutes: 0)
        }
        await #expect(throws: PresentError.self) {
            try await service.startSession(activityId: activity.id!, type: .timebound, timerMinutes: 481)
        }
    }

    @Test func sessionBreakMinutesOutOfRange() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Break Test"))
        await #expect(throws: PresentError.self) {
            try await service.startSession(activityId: activity.id!, type: .rhythm, timerMinutes: 25, breakMinutes: 0)
        }
        await #expect(throws: PresentError.self) {
            try await service.startSession(activityId: activity.id!, type: .rhythm, timerMinutes: 25, breakMinutes: 61)
        }
    }

    @Test func setPreferenceUnknownKeyFails() async throws {
        let service = try makeService()
        await #expect(throws: PresentError.self) {
            try await service.setPreference(key: "nonExistentKey", value: "value")
        }
    }

    @Test func setPreferenceKnownKeySucceeds() async throws {
        let service = try makeService()
        try await service.setPreference(key: PreferenceKey.soundEffectsEnabled, value: "0")
        let value = try await service.getPreference(key: PreferenceKey.soundEffectsEnabled)
        #expect(value == "0")
    }

    @Test func searchQueryTooLong() async throws {
        let service = try makeService()
        let longQuery = String(repeating: "q", count: Constants.maxSearchQueryLength + 1)
        await #expect(throws: PresentError.self) {
            try await service.searchActivities(query: longQuery)
        }
    }

    // MARK: - Set Activity Tags

    @Test func setActivityTagsReplacesExisting() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Tagged"))
        let tag1 = try await service.createTag(name: "frontend")
        let tag2 = try await service.createTag(name: "backend")
        let tag3 = try await service.createTag(name: "urgent")

        try await service.tagActivity(activityId: activity.id!, tagId: tag1.id!)
        try await service.tagActivity(activityId: activity.id!, tagId: tag2.id!)

        let result = try await service.setActivityTags(activityId: activity.id!, tagIds: [tag3.id!])
        #expect(result.count == 1)
        #expect(result.first?.name == "urgent")

        let tags = try await service.tagsForActivity(activityId: activity.id!)
        #expect(tags.count == 1)
        #expect(tags.first?.name == "urgent")
    }

    @Test func setActivityTagsEmptyArray() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Tagged"))
        let tag = try await service.createTag(name: "frontend")
        try await service.tagActivity(activityId: activity.id!, tagId: tag.id!)

        let result = try await service.setActivityTags(activityId: activity.id!, tagIds: [])
        #expect(result.isEmpty)

        let tags = try await service.tagsForActivity(activityId: activity.id!)
        #expect(tags.isEmpty)
    }

    @Test func setActivityTagsInvalidActivity() async throws {
        let service = try makeService()
        await #expect(throws: PresentError.self) {
            try await service.setActivityTags(activityId: 999, tagIds: [])
        }
    }

    @Test func setActivityTagsInvalidTag() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Test"))
        await #expect(throws: PresentError.self) {
            try await service.setActivityTags(activityId: activity.id!, tagIds: [999])
        }
    }

    // MARK: - Backdated Sessions

    @Test func createBackdatedSession() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Backdate"))
        let startedAt = Date().addingTimeInterval(-7200) // 2 hours ago
        let endedAt = Date().addingTimeInterval(-3600)   // 1 hour ago

        let session = try await service.createBackdatedSession(CreateBackdatedSessionInput(
            activityId: activity.id!,
            startedAt: startedAt,
            endedAt: endedAt
        ))
        #expect(session.state == .completed)
        #expect(session.durationSeconds == 3600)
        #expect(session.activityId == activity.id)
    }

    @Test func createBackdatedSessionEndBeforeStart() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Bad"))
        let startedAt = Date().addingTimeInterval(-3600)
        let endedAt = Date().addingTimeInterval(-7200)

        await #expect(throws: PresentError.self) {
            try await service.createBackdatedSession(CreateBackdatedSessionInput(
                activityId: activity.id!,
                startedAt: startedAt,
                endedAt: endedAt
            ))
        }
    }

    @Test func createBackdatedSessionFutureStart() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Future"))
        let startedAt = Date().addingTimeInterval(3600)
        let endedAt = Date().addingTimeInterval(7200)

        await #expect(throws: PresentError.self) {
            try await service.createBackdatedSession(CreateBackdatedSessionInput(
                activityId: activity.id!,
                startedAt: startedAt,
                endedAt: endedAt
            ))
        }
    }

    @Test func createBackdatedSessionOverlap() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Overlap"))

        // Create first session: 3h ago to 2h ago
        _ = try await service.createBackdatedSession(CreateBackdatedSessionInput(
            activityId: activity.id!,
            startedAt: Date().addingTimeInterval(-10800),
            endedAt: Date().addingTimeInterval(-7200)
        ))

        // Try overlapping session: 2.5h ago to 1.5h ago
        await #expect(throws: PresentError.self) {
            try await service.createBackdatedSession(CreateBackdatedSessionInput(
                activityId: activity.id!,
                startedAt: Date().addingTimeInterval(-9000),
                endedAt: Date().addingTimeInterval(-5400)
            ))
        }
    }

    @Test func createBackdatedSessionOverlapWithActive() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Active"))

        // Start a running session
        _ = try await service.startSession(activityId: activity.id!, type: .work)

        // Try backdated session that overlaps with the running session
        await #expect(throws: PresentError.self) {
            try await service.createBackdatedSession(CreateBackdatedSessionInput(
                activityId: activity.id!,
                startedAt: Date().addingTimeInterval(-60),
                endedAt: Date().addingTimeInterval(60)
            ))
        }
    }

    @Test func createBackdatedSessionArchivedActivity() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Archive"))

        // Force archive by adding enough time then archiving
        _ = try await service.createBackdatedSession(CreateBackdatedSessionInput(
            activityId: activity.id!,
            startedAt: Date().addingTimeInterval(-7200),
            endedAt: Date().addingTimeInterval(-3600)
        ))
        _ = try await service.archiveActivity(id: activity.id!)

        await #expect(throws: PresentError.self) {
            try await service.createBackdatedSession(CreateBackdatedSessionInput(
                activityId: activity.id!,
                startedAt: Date().addingTimeInterval(-14400),
                endedAt: Date().addingTimeInterval(-10800)
            ))
        }
    }

    @Test func createBackdatedSessionNoOverlapAdjacent() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Adjacent"))

        let boundary = Date().addingTimeInterval(-7200)

        // Create first session: 3h ago to boundary
        _ = try await service.createBackdatedSession(CreateBackdatedSessionInput(
            activityId: activity.id!,
            startedAt: Date().addingTimeInterval(-10800),
            endedAt: boundary
        ))

        // Adjacent session starting exactly at boundary should succeed
        let session = try await service.createBackdatedSession(CreateBackdatedSessionInput(
            activityId: activity.id!,
            startedAt: boundary,
            endedAt: Date().addingTimeInterval(-3600)
        ))
        #expect(session.state == .completed)
    }

    // MARK: - Activity Summary

    @Test func activitySummaryDateRange() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Summary"))
        _ = try await service.startSession(activityId: activity.id!, type: .work)
        _ = try await service.stopSession()

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!

        let summaries = try await service.activitySummary(from: yesterday, to: tomorrow, includeArchived: true)
        #expect(summaries.count == 1)
        #expect(summaries.first?.activity.title == "Summary")
        #expect(summaries.first?.sessionCount == 1)
    }

    @Test func activitySummaryEmpty() async throws {
        let service = try makeService()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!

        let summaries = try await service.activitySummary(from: yesterday, to: tomorrow, includeArchived: true)
        #expect(summaries.isEmpty)
    }

    // MARK: - Recent Activities

    @Test func recentActivities() async throws {
        let service = try makeService()
        let a1 = try await service.createActivity(CreateActivityInput(title: "Recent 1"))
        let a2 = try await service.createActivity(CreateActivityInput(title: "Recent 2"))
        _ = try await service.createActivity(CreateActivityInput(title: "No Sessions"))

        _ = try await service.startSession(activityId: a1.id!, type: .work)
        _ = try await service.stopSession()
        _ = try await service.startSession(activityId: a2.id!, type: .work)
        _ = try await service.stopSession()

        let recent = try await service.recentActivities(limit: 6)
        #expect(recent.count == 2)
    }

    // MARK: - Session Segments

    private func makeServiceWithWriter() throws -> (PresentService, any DatabaseWriter) {
        let dbManager = try DatabaseManager(inMemory: true)
        return (PresentService(databasePool: dbManager.writer), dbManager.writer)
    }

    @Test func sessionSegmentCreatedOnStart() async throws {
        let (service, dbWriter) = try makeServiceWithWriter()
        let activity = try await service.createActivity(CreateActivityInput(title: "Work"))
        let session = try await service.startSession(activityId: activity.id!, type: .work)

        let segments = try await dbWriter.read { db in
            try SessionSegment
                .filter(SessionSegment.Columns.sessionId == session.id!)
                .fetchAll(db)
        }

        #expect(segments.count == 1)
        #expect(segments[0].endedAt == nil)  // open segment
    }

    @Test func sessionSegmentClosedOnPause() async throws {
        let (service, dbWriter) = try makeServiceWithWriter()
        let activity = try await service.createActivity(CreateActivityInput(title: "Work"))
        let session = try await service.startSession(activityId: activity.id!, type: .work)
        _ = try await service.pauseSession()

        let segments = try await dbWriter.read { db in
            try SessionSegment
                .filter(SessionSegment.Columns.sessionId == session.id!)
                .fetchAll(db)
        }

        #expect(segments.count == 1)
        #expect(segments[0].endedAt != nil)  // segment closed on pause
    }

    @Test func sessionSegmentCreatedOnResume() async throws {
        let (service, dbWriter) = try makeServiceWithWriter()
        let activity = try await service.createActivity(CreateActivityInput(title: "Work"))
        let session = try await service.startSession(activityId: activity.id!, type: .work)
        _ = try await service.pauseSession()
        _ = try await service.resumeSession()

        let segments = try await dbWriter.read { db in
            try SessionSegment
                .filter(SessionSegment.Columns.sessionId == session.id!)
                .fetchAll(db)
        }

        // Two segments: first closed on pause, second open after resume
        #expect(segments.count == 2)
        let open = segments.filter { $0.endedAt == nil }
        let closed = segments.filter { $0.endedAt != nil }
        #expect(open.count == 1)
        #expect(closed.count == 1)
    }

    @Test func segmentSumMatchesDuration() async throws {
        let (service, dbWriter) = try makeServiceWithWriter()
        let activity = try await service.createActivity(CreateActivityInput(title: "Work"))
        _ = try await service.startSession(activityId: activity.id!, type: .work)
        _ = try await service.pauseSession()
        _ = try await service.resumeSession()
        let stopped = try await service.stopSession()

        guard let sessionId = stopped.id, let duration = stopped.durationSeconds else {
            Issue.record("Session missing id or durationSeconds")
            return
        }

        let segments = try await dbWriter.read { db in
            try SessionSegment
                .filter(SessionSegment.Columns.sessionId == sessionId)
                .filter(SessionSegment.Columns.endedAt != nil)
                .fetchAll(db)
        }

        let sumFromSegments = segments.reduce(0) { sum, seg in
            guard let end = seg.endedAt else { return sum }
            return sum + Int(end.timeIntervalSince(seg.startedAt))
        }

        #expect(duration == sumFromSegments)
    }

    @Test func hourlyBreakdownAcrossHours() async throws {
        let (service, dbWriter) = try makeServiceWithWriter()
        let activity = try await service.createActivity(CreateActivityInput(title: "Focus"))

        // Build fixed dates on Jan 15, 2024 in local time
        let cal = Calendar.current
        func makeDate(hour: Int, minute: Int) -> Date {
            var c = DateComponents()
            c.year = 2024; c.month = 1; c.day = 15
            c.hour = hour; c.minute = minute; c.second = 0
            return cal.date(from: c)!
        }

        let sessionStart = makeDate(hour: 1, minute: 30)
        let sessionEnd   = makeDate(hour: 3, minute: 22)
        let seg1Start    = makeDate(hour: 1, minute: 30)
        let seg1End      = makeDate(hour: 1, minute: 35)  // 300s in hour 1
        let seg2Start    = makeDate(hour: 1, minute: 59)  // 60s in hour 1
        let seg2End      = makeDate(hour: 3, minute: 22)  // 3600s in hour 2, 1320s in hour 3

        // Session covers 1:30–3:22; createBackdatedSession inserts one full segment
        let session = try await service.createBackdatedSession(CreateBackdatedSessionInput(
            activityId: activity.id!,
            startedAt: sessionStart,
            endedAt: sessionEnd
        ))

        // Replace with the pause topology: two segments reflecting a pause from 1:35–1:59
        try await dbWriter.write { db in
            try SessionSegment
                .filter(SessionSegment.Columns.sessionId == session.id!)
                .deleteAll(db)

            var s1 = SessionSegment(sessionId: session.id!, startedAt: seg1Start, endedAt: seg1End)
            try s1.insert(db)
            var s2 = SessionSegment(sessionId: session.id!, startedAt: seg2Start, endedAt: seg2End)
            try s2.insert(db)

            // Active time = 300 + 4980 = 5280s
            try db.execute(sql: "UPDATE session SET durationSeconds = 5280 WHERE id = ?", arguments: [session.id!])
        }

        let summary = try await service.dailySummary(date: sessionStart, includeArchived: false)
        let buckets = summary.hourlyBreakdown.sorted { $0.hour < $1.hour }

        // hour 1: seg1 (01:30–01:35 = 300s) + seg2 slice (01:59–02:00 = 60s) = 360s
        // hour 2: seg2 slice (02:00–03:00 = 3600s)
        // hour 3: seg2 slice (03:00–03:22 = 1320s)
        #expect(buckets.count == 3)

        let hour1 = buckets.first { $0.hour == 1 }
        let hour2 = buckets.first { $0.hour == 2 }
        let hour3 = buckets.first { $0.hour == 3 }

        #expect(hour1?.totalSeconds == 360)
        #expect(hour2?.totalSeconds == 3600)
        #expect(hour3?.totalSeconds == 1320)
    }
}
