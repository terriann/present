import Testing
import Foundation
import GRDB
@testable import PresentCore

@Suite("Session Type Conversion Tests")
struct ConvertSessionTypeTests {

    private func makeService() throws -> PresentService {
        let dbManager = try DatabaseManager(inMemory: true)
        return PresentService(databasePool: dbManager.writer)
    }

    // MARK: - Valid Conversions

    @Test func convertWorkToTimebound() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Test"))
        _ = try await service.startSession(activityId: activity.id!, type: .work)

        let converted = try await service.convertSessionType(
            ConvertSessionInput(targetType: .timebound, timerMinutes: 25)
        )

        #expect(converted.sessionType == .timebound)
        #expect(converted.state == .running)
        #expect(converted.timerLengthMinutes == 25)
        #expect(converted.rhythmSessionIndex == nil)
        #expect(converted.breakMinutes == nil)
    }

    @Test func convertTimeboundToWork() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Test"))
        _ = try await service.startSession(activityId: activity.id!, type: .timebound, timerMinutes: 30)

        let converted = try await service.convertSessionType(
            ConvertSessionInput(targetType: .work)
        )

        #expect(converted.sessionType == .work)
        #expect(converted.state == .running)
        #expect(converted.countdownBaseSeconds == 0)
        #expect(converted.rhythmSessionIndex == nil)
        #expect(converted.breakMinutes == nil)
    }

    @Test func convertWorkToRhythm() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Test"))
        _ = try await service.startSession(activityId: activity.id!, type: .work)

        let converted = try await service.convertSessionType(
            ConvertSessionInput(targetType: .rhythm, timerMinutes: 25, breakMinutes: 5)
        )

        #expect(converted.sessionType == .rhythm)
        #expect(converted.state == .running)
        #expect(converted.timerLengthMinutes == 25)
        #expect(converted.breakMinutes == 5)
        #expect(converted.rhythmSessionIndex == 1)
    }

    @Test func convertPausedSessionPreservesState() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Test"))
        _ = try await service.startSession(activityId: activity.id!, type: .work)
        _ = try await service.pauseSession()

        let converted = try await service.convertSessionType(
            ConvertSessionInput(targetType: .timebound, timerMinutes: 25)
        )

        #expect(converted.sessionType == .timebound)
        #expect(converted.state == .paused)
        #expect(converted.timerLengthMinutes == 25)
    }

    @Test func conversionPreservesActivityId() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Test"))
        let session = try await service.startSession(activityId: activity.id!, type: .work)

        let converted = try await service.convertSessionType(
            ConvertSessionInput(targetType: .timebound, timerMinutes: 25)
        )

        #expect(converted.activityId == session.activityId)
        #expect(converted.id == session.id)
        // Compare timestamps within 1 second to avoid floating-point precision issues
        #expect(abs(converted.startedAt.timeIntervalSince(session.startedAt)) < 1)
    }

    @Test func rhythmIndexWrapsAfterFour() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Test"))

        // Create 4 completed rhythm sessions to advance the index
        for _ in 1...4 {
            _ = try await service.startSession(
                activityId: activity.id!, type: .rhythm, timerMinutes: 25, breakMinutes: 5
            )
            _ = try await service.stopSession()
        }

        // Start a work session and convert to rhythm — should wrap to index 1
        _ = try await service.startSession(activityId: activity.id!, type: .work)
        let converted = try await service.convertSessionType(
            ConvertSessionInput(targetType: .rhythm, timerMinutes: 25, breakMinutes: 5)
        )

        #expect(converted.rhythmSessionIndex == 1)
    }

    // MARK: - Error Cases

    @Test func noActiveSessionThrows() async throws {
        let service = try makeService()

        await #expect(throws: PresentError.self) {
            try await service.convertSessionType(
                ConvertSessionInput(targetType: .work)
            )
        }
    }

    @Test func convertToSameTypeThrows() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Test"))
        _ = try await service.startSession(activityId: activity.id!, type: .work)

        await #expect(throws: PresentError.self) {
            try await service.convertSessionType(
                ConvertSessionInput(targetType: .work)
            )
        }
    }

    @Test func rhythmOnSystemActivityThrows() async throws {
        let service = try makeService()
        let breakActivity = try await service.getBreakActivity()

        _ = try await service.startSession(activityId: breakActivity.id!, type: .work)

        await #expect(throws: PresentError.self) {
            try await service.convertSessionType(
                ConvertSessionInput(targetType: .rhythm, timerMinutes: 25, breakMinutes: 5)
            )
        }
    }

    @Test func missingTimerForTimeboundThrows() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Test"))
        _ = try await service.startSession(activityId: activity.id!, type: .work)

        await #expect(throws: PresentError.self) {
            try await service.convertSessionType(
                ConvertSessionInput(targetType: .timebound)
            )
        }
    }

    @Test func missingBreakForRhythmThrows() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Test"))
        _ = try await service.startSession(activityId: activity.id!, type: .work)

        await #expect(throws: PresentError.self) {
            try await service.convertSessionType(
                ConvertSessionInput(targetType: .rhythm, timerMinutes: 25)
            )
        }
    }
}
