import ArgumentParser
import PresentCore

struct StopCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop the current session."
    )

    func run() async throws {
        let service = try CLIServiceFactory.makeService()
        let session = try await service.stopSession()
        let activity = try await service.getActivity(id: session.activityId)

        print("Stopped session for \"\(activity.title)\"")
        if let duration = session.durationSeconds {
            print("Duration: \(TimeFormatting.formatDuration(seconds: duration))")
        }

        IPCClient().send(.sessionStopped)
    }
}
