import Testing
import Foundation
import GRDB
@testable import PresentCore

@Suite("Session Pagination Tests")
struct SessionPaginationTests {

    private func makeService() throws -> PresentService {
        let dbManager = try DatabaseManager(inMemory: true)
        return PresentService(databasePool: dbManager.writer)
    }

    private let rangeStart = Date().addingTimeInterval(-3 * 86400)
    private let rangeEnd = Date().addingTimeInterval(86400)

    /// Creates `count` completed 10 minute sessions, one per hour, oldest first.
    private func seedSessions(_ service: PresentService, activityId: Int64, count: Int) async throws {
        let base = Date().addingTimeInterval(-2 * 86400)
        for i in 0..<count {
            let start = base.addingTimeInterval(Double(i) * 3600)
            _ = try await service.createBackdatedSession(CreateBackdatedSessionInput(
                activityId: activityId,
                startedAt: start,
                endedAt: start.addingTimeInterval(600)
            ))
        }
    }

    // MARK: - Limit and offset

    @Test func limitReturnsOnlyRequestedRows() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Paged"))
        try await seedSessions(service, activityId: try #require(activity.id), count: 5)

        let page = try await service.listSessions(from: rangeStart, to: rangeEnd, limit: 2, offset: 0)
        #expect(page.count == 2)
    }

    @Test func offsetSkipsRowsAndPagesDoNotOverlap() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Paged"))
        try await seedSessions(service, activityId: try #require(activity.id), count: 5)

        let all = try await service.listSessions(from: rangeStart, to: rangeEnd)
        let page1 = try await service.listSessions(from: rangeStart, to: rangeEnd, limit: 2, offset: 0)
        let page2 = try await service.listSessions(from: rangeStart, to: rangeEnd, limit: 2, offset: 2)
        let page3 = try await service.listSessions(from: rangeStart, to: rangeEnd, limit: 2, offset: 4)

        #expect(page3.count == 1)
        #expect((page1 + page2 + page3).map { $0.0.id } == all.map { $0.0.id })
    }

    @Test func offsetBeyondEndReturnsEmpty() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Paged"))
        try await seedSessions(service, activityId: try #require(activity.id), count: 3)

        let page = try await service.listSessions(from: rangeStart, to: rangeEnd, limit: 10, offset: 30)
        #expect(page.isEmpty)
    }

    @Test func noLimitReturnsAllRows() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Paged"))
        try await seedSessions(service, activityId: try #require(activity.id), count: 4)

        let all = try await service.listSessions(from: rangeStart, to: rangeEnd)
        #expect(all.count == 4)
    }

    @Test func equalStartTimesPageDeterministically() async throws {
        let service = try makeService()
        let a = try await service.createActivity(CreateActivityInput(title: "A"))
        let b = try await service.createActivity(CreateActivityInput(title: "B"))
        let c = try await service.createActivity(CreateActivityInput(title: "C"))
        let start = Date().addingTimeInterval(-86400)
        for activity in [a, b, c] {
            _ = try await service.createBackdatedSession(CreateBackdatedSessionInput(
                activityId: try #require(activity.id),
                startedAt: start,
                endedAt: start.addingTimeInterval(600)
            ))
        }

        let all = try await service.listSessions(from: rangeStart, to: rangeEnd)
        var paged: [Int64?] = []
        for offset in 0..<3 {
            let page = try await service.listSessions(from: rangeStart, to: rangeEnd, limit: 1, offset: offset)
            paged.append(contentsOf: page.map { $0.0.id })
        }
        #expect(paged == all.map { $0.0.id })
    }

    // MARK: - countSessions

    @Test func countMatchesUnpaginatedList() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Counted"))
        try await seedSessions(service, activityId: try #require(activity.id), count: 6)

        let count = try await service.countSessions(from: rangeStart, to: rangeEnd)
        let all = try await service.listSessions(from: rangeStart, to: rangeEnd)
        #expect(count == 6)
        #expect(count == all.count)
    }

    @Test func countRespectsTypeAndActivityFilters() async throws {
        let service = try makeService()
        let a = try await service.createActivity(CreateActivityInput(title: "A"))
        let b = try await service.createActivity(CreateActivityInput(title: "B"))
        try await seedSessions(service, activityId: try #require(a.id), count: 3)
        try await seedSessions(service, activityId: try #require(b.id), count: 2)

        let aCount = try await service.countSessions(from: rangeStart, to: rangeEnd, activityId: a.id)
        let workCount = try await service.countSessions(from: rangeStart, to: rangeEnd, type: .work)
        let rhythmCount = try await service.countSessions(from: rangeStart, to: rangeEnd, type: .rhythm)
        #expect(aCount == 3)
        #expect(workCount == 5)
        #expect(rhythmCount == 0)
    }

    @Test func countExcludesArchivedWhenRequested() async throws {
        let service = try makeService()
        let a = try await service.createActivity(CreateActivityInput(title: "Keep"))
        let b = try await service.createActivity(CreateActivityInput(title: "Archive"))
        try await seedSessions(service, activityId: try #require(a.id), count: 2)
        try await seedSessions(service, activityId: try #require(b.id), count: 3)
        _ = try await service.archiveActivity(id: try #require(b.id))

        let withArchived = try await service.countSessions(from: rangeStart, to: rangeEnd, includeArchived: true)
        let withoutArchived = try await service.countSessions(from: rangeStart, to: rangeEnd, includeArchived: false)
        #expect(withArchived == 5)
        #expect(withoutArchived == 2)
    }

    @Test func countExcludesActiveSessionUnlessIncluded() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Live"))
        try await seedSessions(service, activityId: try #require(activity.id), count: 2)
        _ = try await service.startSession(activityId: try #require(activity.id), type: .work)

        let closedOnly = try await service.countSessions(from: rangeStart, to: rangeEnd)
        let withActive = try await service.countSessions(from: rangeStart, to: rangeEnd, includeActive: true)
        #expect(closedOnly == 2)
        #expect(withActive == 3)
    }

    // MARK: - activityIds filter

    @Test func activityIdsFilterMatchesMultipleActivities() async throws {
        let service = try makeService()
        let a = try await service.createActivity(CreateActivityInput(title: "Deep Work"))
        let b = try await service.createActivity(CreateActivityInput(title: "Deep Reading"))
        let c = try await service.createActivity(CreateActivityInput(title: "Email"))
        try await seedSessions(service, activityId: try #require(a.id), count: 2)
        try await seedSessions(service, activityId: try #require(b.id), count: 2)
        try await seedSessions(service, activityId: try #require(c.id), count: 3)

        let ids = [try #require(a.id), try #require(b.id)]
        let count = try await service.countSessions(from: rangeStart, to: rangeEnd, activityIds: ids)
        let page = try await service.listSessions(from: rangeStart, to: rangeEnd, activityIds: ids, limit: 3, offset: 0)
        #expect(count == 4)
        #expect(page.count == 3)
        #expect(page.allSatisfy { $0.1.title.hasPrefix("Deep") })
    }

    @Test func emptyActivityIdsMatchesNothing() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Any"))
        try await seedSessions(service, activityId: try #require(activity.id), count: 2)

        let count = try await service.countSessions(from: rangeStart, to: rangeEnd, activityIds: [])
        #expect(count == 0)
    }
}
