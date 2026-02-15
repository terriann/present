import ArgumentParser
import PresentCore

struct ResumeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resume",
        abstract: "Resume a paused session."
    )

    func run() async throws {
        let service = try CLIServiceFactory.makeService()
        let session = try await service.resumeSession()
        let activity = try await service.getActivity(id: session.activityId)
        print("Resumed session for \"\(activity.title)\"")

        IPCClient().send(.sessionResumed)
    }
}
