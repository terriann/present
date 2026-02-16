import ArgumentParser
import Foundation
import PresentCore

struct SessionPauseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pause",
        abstract: "Pause the current session."
    )

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        let session = try await service.pauseSession()
        let activity = try await service.getActivity(id: session.activityId)

        switch outputOptions.format {
        case .json:
            try outputOptions.printJSON(session.toJSONDict(activity: activity))

        case .text:
            let textFields = session.toTextFields(activity: activity)
            if try outputOptions.printTextField(textFields) { break }

            print("Paused session for \"\(activity.title)\"")

        case .csv:
            print("CSV output not supported for session pause.")
            throw ExitCode.failure
        }

        IPCClient().send(.sessionPaused)
    }
}
