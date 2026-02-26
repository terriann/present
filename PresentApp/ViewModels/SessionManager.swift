import Foundation
import PresentCore

@MainActor @Observable
final class SessionManager {
    // MARK: - Dependencies

    private let service: PresentService

    // MARK: - Initialization

    init(service: PresentService) {
        self.service = service
    }

    // MARK: - Session Lifecycle

    func startSession(activityId: Int64, type: SessionType, timerMinutes: Int? = nil, breakMinutes: Int? = nil) async throws -> (Session, Activity) {
        let session = try await service.startSession(
            activityId: activityId,
            type: type,
            timerMinutes: timerMinutes,
            breakMinutes: breakMinutes
        )
        let activity = try await service.getActivity(id: activityId)
        return (session, activity)
    }

    func pauseSession() async throws -> Session {
        try await service.pauseSession()
    }

    func resumeSession() async throws -> Session {
        try await service.resumeSession()
    }

    func stopSession() async throws -> Session {
        try await service.stopSession()
    }

    func cancelSession() async throws {
        try await service.cancelSession()
    }

    // MARK: - Break Activity

    func getBreakActivity() async throws -> Activity {
        try await service.getBreakActivity()
    }
}
