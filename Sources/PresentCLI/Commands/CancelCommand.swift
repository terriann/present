import ArgumentParser
import PresentCore

struct CancelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cancel",
        abstract: "Cancel the current session without logging it."
    )

    func run() async throws {
        let service = try CLIServiceFactory.makeService()

        guard let (_, activity) = try await service.currentSession() else {
            print("No active session to cancel.")
            throw ExitCode.failure
        }

        try await service.cancelSession()
        print("Cancelled session for \"\(activity.title)\"")

        IPCClient().send(.sessionCancelled)
    }
}
