import ArgumentParser
import PresentCore

struct PauseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pause",
        abstract: "Pause the current session."
    )

    func run() async throws {
        let service = try CLIServiceFactory.makeService()
        let session = try await service.pauseSession()
        let activity = try await service.getActivity(id: session.activityId)
        print("Paused session for \"\(activity.title)\"")

        IPCClient().send(.sessionPaused)
    }
}
