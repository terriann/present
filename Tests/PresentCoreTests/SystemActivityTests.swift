import Testing
import Foundation
import GRDB
@testable import PresentCore

@Suite("System Activity Tests")
struct SystemActivityTests {

    private func makeService() throws -> PresentService {
        let dbManager = try DatabaseManager(inMemory: true)
        return PresentService(databasePool: dbManager.writer)
    }

    // MARK: - Break Activity Exists

    @Test func breakActivityExistsAfterMigration() async throws {
        let service = try makeService()
        let breakActivity = try await service.getBreakActivity()
        #expect(breakActivity.isSystem == true)
        #expect(breakActivity.title == Constants.breakActivityTitle)
        #expect(breakActivity.title == "Break")
    }

    @Test func getBreakActivityReturnsCorrectActivity() async throws {
        let service = try makeService()
        let breakActivity = try await service.getBreakActivity()

        #expect(breakActivity.id != nil)
        #expect(breakActivity.isSystem == true)
        #expect(breakActivity.isArchived == false)
        #expect(breakActivity.title == "Break")
    }

    // MARK: - Cannot Modify System Activity

    @Test func cannotUpdateSystemActivity() async throws {
        let service = try makeService()
        let breakActivity = try await service.getBreakActivity()

        do {
            _ = try await service.updateActivity(
                id: breakActivity.id!,
                UpdateActivityInput(title: "Renamed Break")
            )
            Issue.record("Expected cannotModifySystemActivity error")
        } catch let error as PresentError {
            guard case .cannotModifySystemActivity = error else {
                Issue.record("Expected cannotModifySystemActivity but got \(error)")
                return
            }
        }
    }

    @Test func cannotDeleteSystemActivity() async throws {
        let service = try makeService()
        let breakActivity = try await service.getBreakActivity()

        do {
            try await service.deleteActivity(id: breakActivity.id!)
            Issue.record("Expected cannotModifySystemActivity error")
        } catch let error as PresentError {
            guard case .cannotModifySystemActivity = error else {
                Issue.record("Expected cannotModifySystemActivity but got \(error)")
                return
            }
        }
    }

    @Test func cannotArchiveSystemActivity() async throws {
        let service = try makeService()
        let breakActivity = try await service.getBreakActivity()

        do {
            _ = try await service.archiveActivity(id: breakActivity.id!)
            Issue.record("Expected cannotModifySystemActivity error")
        } catch let error as PresentError {
            guard case .cannotModifySystemActivity = error else {
                Issue.record("Expected cannotModifySystemActivity but got \(error)")
                return
            }
        }
    }

    // MARK: - System Activity in Lists

    @Test func systemActivityExcludedByDefault() async throws {
        let service = try makeService()
        _ = try await service.createActivity(CreateActivityInput(title: "User Activity"))

        let activities = try await service.listActivities(includeArchived: false)
        #expect(activities.count == 1)
        #expect(activities.allSatisfy { !$0.isSystem })

        let allActivities = try await service.listActivities(includeArchived: true)
        #expect(allActivities.allSatisfy { !$0.isSystem })
    }

    @Test func systemActivityIncludedWhenRequested() async throws {
        let service = try makeService()
        _ = try await service.createActivity(CreateActivityInput(title: "User Activity"))

        let activities = try await service.listActivities(includeArchived: false, includeSystem: true)
        #expect(activities.count == 2)
        #expect(activities.contains { $0.isSystem })
        #expect(activities.contains { !$0.isSystem })
    }

    @Test func systemActivitySortsFirst() async throws {
        let service = try makeService()
        _ = try await service.createActivity(CreateActivityInput(title: "Alpha"))
        _ = try await service.createActivity(CreateActivityInput(title: "Zeta"))

        let activities = try await service.listActivities(includeArchived: false, includeSystem: true)
        #expect(activities.first?.isSystem == true)
        #expect(activities.first?.title == "Break")
    }

    @Test func backwardCompatibleListExcludesSystem() async throws {
        let service = try makeService()
        _ = try await service.createActivity(CreateActivityInput(title: "User Activity"))

        // One-parameter form (protocol extension) should exclude system
        let activities = try await service.listActivities(includeArchived: true)
        #expect(activities.allSatisfy { !$0.isSystem })
    }

    @Test func systemActivityExcludedFromRecentActivities() async throws {
        let service = try makeService()
        let userActivity = try await service.createActivity(CreateActivityInput(title: "User Activity"))
        let breakActivity = try await service.getBreakActivity()

        // Start and stop sessions on both to make them "recent"
        _ = try await service.startSession(activityId: userActivity.id!, type: .work)
        _ = try await service.stopSession()

        _ = try await service.startSession(activityId: breakActivity.id!, type: .rhythm)
        _ = try await service.stopSession()

        let recent = try await service.recentActivities(limit: 10)
        #expect(recent.allSatisfy { !$0.isSystem })
    }

    // MARK: - System Activity Excluded from Limit

    @Test func systemActivityExcludedFromActivityLimitCount() async throws {
        let service = try makeService()

        // Create exactly maxActiveActivities user activities
        for i in 1...PresentService.maxActiveActivities {
            _ = try await service.createActivity(CreateActivityInput(title: "Activity \(i)"))
        }

        // Break system activity should still exist and not count toward limit
        let breakActivity = try await service.getBreakActivity()
        #expect(breakActivity.isSystem == true)

        // Creating one more user activity should fail at the limit
        await #expect(throws: PresentError.self) {
            try await service.createActivity(CreateActivityInput(title: "Over Limit"))
        }
    }

    // MARK: - Break Session Behavior

    @Test func startingSessionOnBreakActivityWorks() async throws {
        let service = try makeService()
        let breakActivity = try await service.getBreakActivity()

        let session = try await service.startSession(
            activityId: breakActivity.id!,
            type: .rhythm,
            breakMinutes: 5
        )

        #expect(session.activityId == breakActivity.id!)
        #expect(session.sessionType == .rhythm)
        #expect(session.state == .running)
    }

    @Test func getBreakActivitySelfHealsIfMissing() async throws {
        let dbManager = try DatabaseManager(inMemory: true)
        let service = PresentService(databasePool: dbManager.writer)

        // Verify Break exists after migration
        let original = try await service.getBreakActivity()
        #expect(original.isSystem == true)

        // Delete Break via raw SQL to simulate DB corruption
        try await dbManager.writer.write { db in
            try db.execute(sql: "DELETE FROM activity WHERE isSystem = 1")
        }

        // getBreakActivity should self-heal by re-creating it
        let restored = try await service.getBreakActivity()
        #expect(restored.isSystem == true)
        #expect(restored.title == "Break")
        #expect(restored.id != nil)
    }

    @Test func breakSessionGetsNilRhythmSessionIndex() async throws {
        let service = try makeService()
        let breakActivity = try await service.getBreakActivity()

        let session = try await service.startSession(
            activityId: breakActivity.id!,
            type: .rhythm,
            breakMinutes: 5
        )

        #expect(session.rhythmSessionIndex == nil)
    }
}
