import Testing
import Foundation
@testable import PresentCore

@Suite("Concurrency Tests")
struct ConcurrencyTests {

    private func makeService() throws -> PresentService {
        let dbManager = try DatabaseManager(inMemory: true)
        return PresentService(databasePool: dbManager.writer)
    }

    /// Run `count` concurrent copies of `operation`, returning how many succeeded vs failed.
    private func raceConcurrently<T: Sendable>(
        count: Int = 10,
        operation: @escaping @Sendable () async throws -> T
    ) async -> (successes: Int, failures: Int) {
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<count {
                group.addTask {
                    do {
                        _ = try await operation()
                        return true
                    } catch {
                        return false
                    }
                }
            }

            var successes = 0
            var failures = 0
            for await succeeded in group {
                if succeeded { successes += 1 } else { failures += 1 }
            }
            return (successes, failures)
        }
    }

    // MARK: - Session Start

    @Test func concurrentSessionStartsAllowExactlyOne() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Race"))

        let result = await raceConcurrently {
            try await service.startSession(activityId: activity.id!, type: .work)
        }

        #expect(result.successes == 1)
        #expect(result.failures == 9)

        // Post-condition: exactly one running session
        let current = try await service.currentSession()
        #expect(current != nil)
        #expect(current?.0.state == .running)
    }

    // MARK: - Session Pause

    @Test func concurrentPauseAttemptsAllowExactlyOne() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Pause Race"))
        _ = try await service.startSession(activityId: activity.id!, type: .work)

        let result = await raceConcurrently {
            try await service.pauseSession()
        }

        #expect(result.successes == 1)
        #expect(result.failures == 9)

        // Post-condition: session is paused
        let current = try await service.currentSession()
        #expect(current != nil)
        #expect(current?.0.state == .paused)
    }

    // MARK: - Session Resume

    @Test func concurrentResumeAttemptsAllowExactlyOne() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Resume Race"))
        _ = try await service.startSession(activityId: activity.id!, type: .work)
        _ = try await service.pauseSession()

        let result = await raceConcurrently {
            try await service.resumeSession()
        }

        #expect(result.successes == 1)
        #expect(result.failures == 9)

        // Post-condition: session is running again
        let current = try await service.currentSession()
        #expect(current != nil)
        #expect(current?.0.state == .running)
    }

    // MARK: - Session Stop

    @Test func concurrentStopAttemptsAllowExactlyOne() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Stop Race"))
        _ = try await service.startSession(activityId: activity.id!, type: .work)

        let result = await raceConcurrently {
            try await service.stopSession()
        }

        #expect(result.successes == 1)
        #expect(result.failures == 9)

        // Post-condition: no active session
        let current = try await service.currentSession()
        #expect(current == nil)
    }

    // MARK: - Session Cancel

    @Test func concurrentCancelAttemptsAllowExactlyOne() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Cancel Race"))
        _ = try await service.startSession(activityId: activity.id!, type: .work)

        let result = await raceConcurrently {
            try await service.cancelSession()
        }

        #expect(result.successes == 1)
        #expect(result.failures == 9)

        // Post-condition: no active session
        let current = try await service.currentSession()
        #expect(current == nil)
    }

    // MARK: - Activity Limit

    @Test func activityCreationRacingAgainstLimit() async throws {
        let service = try makeService()

        // Create 49 activities (limit is 50)
        for i in 1...49 {
            _ = try await service.createActivity(CreateActivityInput(title: "Activity \(i)"))
        }

        let result = await raceConcurrently(count: 5) {
            try await service.createActivity(CreateActivityInput(title: "Racer \(UUID().uuidString.prefix(6))"))
        }

        #expect(result.successes == 1)
        #expect(result.failures == 4)
    }

    // MARK: - Mixed Start and Stop

    @Test func concurrentStartAndStopProducesConsistentState() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Mixed Race"))
        _ = try await service.startSession(activityId: activity.id!, type: .work)

        // Fire one start and one stop concurrently
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = try? await service.stopSession()
            }
            group.addTask {
                _ = try? await service.startSession(activityId: activity.id!, type: .work)
            }
        }

        // Either the stop won (then start created a new session → running)
        // or the start failed because session was already active (then stop completed → no session)
        // or the stop completed then start succeeded → running
        // All valid: final state is either a running session or no session
        let current = try await service.currentSession()
        if let (session, _) = current {
            #expect(session.state == .running)
        }
        // nil is also valid — both outcomes are acceptable
    }
}
