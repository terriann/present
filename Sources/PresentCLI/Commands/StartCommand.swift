import ArgumentParser
import PresentCore

struct StartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start a session for an activity."
    )

    @Argument(help: "Activity name (creates if it doesn't exist).")
    var activityName: String

    @Option(name: .long, help: "Session type: work, rhythm, timebound, timebox.")
    var type: String = "work"

    @Option(name: .long, help: "Timer duration in minutes (for rhythm/timebound).")
    var minutes: Int?

    func run() async throws {
        guard let sessionType = SessionType(rawValue: type) else {
            print("Invalid session type: \(type). Use: work, rhythm, timebound, timebox.")
            throw ExitCode.failure
        }

        let service = try CLIServiceFactory.makeService()

        // Find or create activity
        let activities = try await service.listActivities(includeArchived: false)
        let activity: Activity
        if let existing = activities.first(where: { $0.title.lowercased() == activityName.lowercased() }) {
            activity = existing
        } else {
            activity = try await service.createActivity(CreateActivityInput(title: activityName))
            print("Created activity: \(activity.title)")
        }

        let session = try await service.startSession(
            activityId: activity.id!,
            type: sessionType,
            timerMinutes: minutes,
            plannedStart: nil,
            plannedEnd: nil
        )

        let config = SessionTypeConfig.config(for: session.sessionType)
        print("Started \(config.displayName) for \"\(activity.title)\"")

        if let timer = session.timerLengthMinutes {
            print("Timer: \(timer) minutes")
        }

        IPCClient().send(.sessionStarted)
    }
}
