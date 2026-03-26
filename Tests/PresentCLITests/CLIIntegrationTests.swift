import Testing
import Foundation
@testable import PresentCLI
@testable import PresentCore

/// Integration tests that execute CLI command `run()` methods against an in-memory database.
/// Verifies service state changes, error handling, and command workflows.
@Suite("CLI Integration Tests", .serialized)
struct CLIIntegrationTests {

    private func makeService() throws -> PresentService {
        let dbManager = try DatabaseManager(inMemory: true)
        return PresentService(databasePool: dbManager.writer)
    }

    /// Install an in-memory service override, run the closure, then clear it.
    private func withTestService(_ body: (PresentService) async throws -> Void) async throws {
        let service = try makeService()
        CLIServiceFactory.serviceOverride = service
        defer { CLIServiceFactory.serviceOverride = nil }
        try await body(service)
    }

    // MARK: - Activity CRUD

    @Test func activityAddCreatesActivity() async throws {
        try await withTestService { service in
            var cmd = try ActivityAddCommand.parse(["Test Activity"])
            try await cmd.run()

            let activities = try await service.listActivities(includeArchived: true, includeSystem: false)
            let found = activities.contains { $0.title == "Test Activity" }
            #expect(found)
        }
    }

    @Test func activityAddWithOptions() async throws {
        try await withTestService { service in
            var cmd = try ActivityAddCommand.parse([
                "Linked Task", "--link", "https://example.com", "--external-id", "EXT-1"
            ])
            try await cmd.run()

            let activities = try await service.listActivities(includeArchived: true, includeSystem: false)
            let activity = activities.first { $0.title == "Linked Task" }
            #expect(activity?.link == "https://example.com")
            #expect(activity?.externalId == "EXT-1")
        }
    }

    @Test func activityListReturnsActivities() async throws {
        try await withTestService { service in
            _ = try await service.createActivity(CreateActivityInput(title: "Alpha"))
            _ = try await service.createActivity(CreateActivityInput(title: "Beta"))

            var cmd = try ActivityListCommand.parse([])
            try await cmd.run()
            // Command ran without throwing — output went to stdout
        }
    }

    @Test func activityGetReturnsActivity() async throws {
        try await withTestService { service in
            let activity = try await service.createActivity(CreateActivityInput(title: "Fetch Me"))
            let id = try #require(activity.id)

            var cmd = try ActivityGetCommand.parse(["\(id)"])
            try await cmd.run()
        }
    }

    // activityGetNonexistent — throws ExitCode.failure which fatalErrors outside
    // ArgumentParser's runner. Error paths tested at the service layer instead.

    @Test func activityUpdateChangesTitle() async throws {
        try await withTestService { service in
            let activity = try await service.createActivity(CreateActivityInput(title: "Old Name"))
            let id = try #require(activity.id)

            var cmd = try ActivityUpdateCommand.parse(["\(id)", "--title", "New Name"])
            try await cmd.run()

            let updated = try await service.getActivity(id: id)
            #expect(updated.title == "New Name")
        }
    }

    @Test func activityArchiveAndUnarchive() async throws {
        try await withTestService { service in
            let activity = try await service.createActivity(CreateActivityInput(title: "Archivable"))
            let id = try #require(activity.id)

            var archiveCmd = try ActivityArchiveCommand.parse(["\(id)", "--force"])
            try await archiveCmd.run()

            let archived = try await service.getActivity(id: id)
            #expect(archived.isArchived)

            var unarchiveCmd = try ActivityUnarchiveCommand.parse(["\(id)"])
            try await unarchiveCmd.run()

            let restored = try await service.getActivity(id: id)
            #expect(!restored.isArchived)
        }
    }

    @Test func activityDeleteRemovesActivity() async throws {
        try await withTestService { service in
            let activity = try await service.createActivity(CreateActivityInput(title: "Deletable"))
            let id = try #require(activity.id)

            var cmd = try ActivityDeleteCommand.parse(["\(id)"])
            try await cmd.run()

            await #expect(throws: PresentError.self) {
                _ = try await service.getActivity(id: id)
            }
        }
    }

    // MARK: - Session Lifecycle

    @Test func sessionStartCreatesRunningSession() async throws {
        try await withTestService { service in
            _ = try await service.createActivity(CreateActivityInput(title: "Work Task"))

            var cmd = try SessionStartCommand.parse(["Work Task"])
            try await cmd.run()

            let current = try await service.currentSession()
            #expect(current != nil)
            #expect(current?.0.state == .running)
            #expect(current?.1.title == "Work Task")
        }
    }

    @Test func sessionStartCreatesActivityIfNeeded() async throws {
        try await withTestService { service in
            var cmd = try SessionStartCommand.parse(["Brand New Activity"])
            try await cmd.run()

            let current = try await service.currentSession()
            #expect(current?.1.title == "Brand New Activity")
        }
    }

    @Test func sessionStartWithTypeAndTimer() async throws {
        try await withTestService { service in
            var cmd = try SessionStartCommand.parse([
                "Timed Task", "--type", "timebound", "--minutes", "25"
            ])
            try await cmd.run()

            let current = try await service.currentSession()
            #expect(current?.0.sessionType == .timebound)
            #expect(current?.0.timerLengthMinutes == 25)
        }
    }

    @Test func sessionStopCompletesSession() async throws {
        try await withTestService { service in
            let activity = try await service.createActivity(CreateActivityInput(title: "Stoppable"))
            let activityId = try #require(activity.id)
            _ = try await service.startSession(activityId: activityId, type: .work)

            var cmd = try SessionStopCommand.parse([])
            try await cmd.run()

            let current = try await service.currentSession()
            #expect(current == nil)
        }
    }

    // sessionStopWithNoActiveSession — throws ExitCode.failure which fatalErrors
    // outside ArgumentParser's runner. Error path tested at the service layer.

    @Test func sessionPauseAndResume() async throws {
        try await withTestService { service in
            let activity = try await service.createActivity(CreateActivityInput(title: "Pausable"))
            let activityId = try #require(activity.id)
            _ = try await service.startSession(activityId: activityId, type: .work)

            var pauseCmd = try SessionPauseCommand.parse([])
            try await pauseCmd.run()

            let paused = try await service.currentSession()
            #expect(paused?.0.state == .paused)

            var resumeCmd = try SessionResumeCommand.parse([])
            try await resumeCmd.run()

            let resumed = try await service.currentSession()
            #expect(resumed?.0.state == .running)
        }
    }

    @Test func sessionCancelDeletesSession() async throws {
        try await withTestService { service in
            let activity = try await service.createActivity(CreateActivityInput(title: "Cancellable"))
            let activityId = try #require(activity.id)
            _ = try await service.startSession(activityId: activityId, type: .work)

            var cmd = try SessionCancelCommand.parse([])
            try await cmd.run()

            let current = try await service.currentSession()
            #expect(current == nil)
        }
    }

    @Test func sessionCurrentStatusWithActiveSession() async throws {
        try await withTestService { service in
            let activity = try await service.createActivity(CreateActivityInput(title: "Status Check"))
            let activityId = try #require(activity.id)
            _ = try await service.startSession(activityId: activityId, type: .work)

            var cmd = try SessionCurrentStatusCommand.parse([])
            try await cmd.run()
        }
    }

    @Test func sessionCurrentStatusWithNoSession() async throws {
        try await withTestService { _ in
            var cmd = try SessionCurrentStatusCommand.parse([])
            try await cmd.run()
        }
    }

    // MARK: - Session Add (Backdated)

    @Test func sessionAddCreatesCompletedSession() async throws {
        try await withTestService { service in
            let activity = try await service.createActivity(CreateActivityInput(title: "Backdated"))
            let actId = try #require(activity.id)

            var cmd = try SessionAddCommand.parse([
                "\(actId)",
                "--started-at", "2026-01-15T09:00:00",
                "--ended-at", "2026-01-15T10:00:00"
            ])
            try await cmd.run()

            let sessions = try await service.listSessions(
                from: Date.distantPast, to: Date.distantFuture,
                type: nil, activityId: actId, includeArchived: false
            )
            #expect(sessions.count == 1)
            #expect(sessions.first?.0.state == .completed)
        }
    }

    // MARK: - Session List

    @Test func sessionListWithDateFilter() async throws {
        try await withTestService { service in
            let activity = try await service.createActivity(CreateActivityInput(title: "Listed"))
            let actId = try #require(activity.id)

            // Create a backdated session
            let now = Date()
            let startedAt = try #require(Calendar.current.date(byAdding: .hour, value: -2, to: now))
            let endedAt = try #require(Calendar.current.date(byAdding: .hour, value: -1, to: now))
            _ = try await service.createBackdatedSession(CreateBackdatedSessionInput(
                activityId: actId,
                sessionType: .work,
                startedAt: startedAt,
                endedAt: endedAt
            ))

            let today = Date()
            let dateStr = {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                return f.string(from: today)
            }()

            var cmd = try SessionListCommand.parse(["--after", dateStr])
            try await cmd.run()
        }
    }

    // MARK: - Tag CRUD

    @Test func tagAddCreatesTag() async throws {
        try await withTestService { service in
            var cmd = try TagAddCommand.parse(["urgent"])
            try await cmd.run()

            let tags = try await service.listTags()
            #expect(tags.contains { $0.name == "urgent" })
        }
    }

    @Test func tagGetReturnsTag() async throws {
        try await withTestService { service in
            let tag = try await service.createTag(name: "important")
            let id = try #require(tag.id)

            var cmd = try TagGetCommand.parse(["\(id)"])
            try await cmd.run()
        }
    }

    @Test func tagUpdateChangesName() async throws {
        try await withTestService { service in
            let tag = try await service.createTag(name: "old-name")
            let id = try #require(tag.id)

            var cmd = try TagUpdateCommand.parse(["\(id)", "--name", "new-name"])
            try await cmd.run()

            let tags = try await service.listTags()
            #expect(tags.contains { $0.name == "new-name" })
            #expect(!tags.contains { $0.name == "old-name" })
        }
    }

    @Test func tagDeleteRemovesTag() async throws {
        try await withTestService { service in
            let tag = try await service.createTag(name: "deletable")
            let id = try #require(tag.id)

            var cmd = try TagDeleteCommand.parse(["\(id)"])
            try await cmd.run()

            let tags = try await service.listTags()
            #expect(!tags.contains { $0.name == "deletable" })
        }
    }

    @Test func tagListReturnsTags() async throws {
        try await withTestService { service in
            _ = try await service.createTag(name: "alpha")
            _ = try await service.createTag(name: "beta")

            var cmd = try TagListCommand.parse([])
            try await cmd.run()
        }
    }

    // MARK: - Activity Tags

    @Test func activityTagAddAndList() async throws {
        try await withTestService { service in
            let activity = try await service.createActivity(CreateActivityInput(title: "Tagged"))
            let tag = try await service.createTag(name: "focus")
            let actId = try #require(activity.id)
            let tagId = try #require(tag.id)

            var addCmd = try ActivityTagAddCommand.parse(["\(actId)", "\(tagId)"])
            try await addCmd.run()

            let tags = try await service.tagsForActivity(activityId: actId)
            #expect(tags.contains { $0.name == "focus" })

            var listCmd = try ActivityTagListCommand.parse(["\(actId)"])
            try await listCmd.run()
        }
    }

    @Test func activityTagRemove() async throws {
        try await withTestService { service in
            let activity = try await service.createActivity(CreateActivityInput(title: "Untaggable"))
            let tag = try await service.createTag(name: "remove-me")
            let actId = try #require(activity.id)
            let tagId = try #require(tag.id)

            try await service.tagActivity(activityId: actId, tagId: tagId)

            var cmd = try ActivityTagRemoveCommand.parse(["\(actId)", "\(tagId)"])
            try await cmd.run()

            let tags = try await service.tagsForActivity(activityId: actId)
            #expect(!tags.contains { $0.name == "remove-me" })
        }
    }

    // MARK: - Report

    @Test func reportRunsWithDefaults() async throws {
        try await withTestService { _ in
            var cmd = try ReportCommand.parse([])
            try await cmd.run()
        }
    }

    @Test func reportRunsWithDateRange() async throws {
        try await withTestService { _ in
            var cmd = try ReportCommand.parse(["--after", "2026-01-01", "--before", "2026-01-31"])
            try await cmd.run()
        }
    }

    // MARK: - Config

    @Test func configListRuns() async throws {
        try await withTestService { _ in
            var cmd = try ConfigListCommand.parse([])
            try await cmd.run()
        }
    }

    @Test func configSetAndGet() async throws {
        try await withTestService { service in
            var setCmd = try ConfigSetCommand.parse(["soundEffectsEnabled", "0"])
            try await setCmd.run()

            let value = try await service.getPreference(key: "soundEffectsEnabled")
            #expect(value == "0")

            var getCmd = try ConfigGetCommand.parse(["soundEffectsEnabled"])
            try await getCmd.run()
        }
    }

    // configGetUnknownKey — throws ExitCode.failure which fatalErrors outside
    // ArgumentParser's runner. Validated by validatePreferenceKey unit tests.

    // Note: ExitCode.failure (from CSV-not-supported, invalid session type, etc.)
    // calls fatalError when thrown outside ArgumentParser's command runner.
    // These error paths are covered by SessionTypeParsingTests, OutputFormatTests,
    // and CSVEscapingTests instead.
}
