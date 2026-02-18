import ArgumentParser
import Foundation
import PresentCore

struct SessionCancelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cancel",
        abstract: "Cancel the current session without logging it.",
        discussion: """
            Discards the current session entirely. Unlike `stop`, the session \
            is not saved and no duration is recorded. Useful for sessions \
            started by mistake.

            ## Examples

            # Cancel the current session
            $ present-cli session cancel

            # Cancel and confirm via text output
            $ present-cli session cancel -f text
            """
    )

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()

        guard let (session, activity) = try await service.currentSession() else {
            print("No active session to cancel.")
            throw ExitCode.failure
        }

        try await service.cancelSession()

        switch outputOptions.format {
        case .json:
            var dict = session.toJSONDict(activity: activity)
            dict["cancelled"] = true
            try outputOptions.printJSON(dict)

        case .text:
            var textFields = activity.toTextFields()
            textFields["cancelled"] = "true"
            if try outputOptions.printTextField(textFields) { break }

            print("Cancelled session for \"\(activity.title)\"")

        case .csv:
            print("CSV output not supported for session cancel.")
            throw ExitCode.failure
        }

        IPCClient().send(.sessionCancelled)
    }
}
