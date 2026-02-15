import ArgumentParser
import PresentCore

struct NoteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "note",
        abstract: "Append a note to the current activity."
    )

    @Argument(help: "Text to append to the activity's notes.")
    var text: String

    func run() async throws {
        let service = try CLIServiceFactory.makeService()

        guard let (session, activity) = try await service.currentSession() else {
            print("No active session. Start a session first.")
            throw ExitCode.failure
        }

        _ = try await service.appendNote(activityId: session.activityId, text: text)
        print("Note appended to \"\(activity.title)\"")

        IPCClient().send(.activityUpdated)
    }
}
