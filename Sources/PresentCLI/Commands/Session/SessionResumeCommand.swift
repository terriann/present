import ArgumentParser
import Foundation
import PresentCore

struct SessionResumeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resume",
        abstract: "Resume a paused session.",
        discussion: """
            Resumes a previously paused session. The session timer continues \
            from where it left off. Returns an error if no session is paused.

            ## Examples

            # Resume the paused session
            $ present-cli session resume

            # Resume and display as text
            $ present-cli session resume -f text
            """
    )

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        let session = try await service.resumeSession()
        let activity = try await service.getActivity(id: session.activityId)

        switch outputOptions.format {
        case .json:
            try outputOptions.printJSON(session.toJSONDict(activity: activity))

        case .text:
            let textFields = session.toTextFields(activity: activity)
            if try outputOptions.printTextField(textFields) { break }

            print("Resumed session for \"\(activity.title)\"")

        case .csv:
            print("CSV output not supported for session resume.")
            throw ExitCode.failure
        }

        IPCClient().send(.sessionResumed)
    }
}
