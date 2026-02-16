import ArgumentParser
import Foundation
import PresentCore

struct SessionResumeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resume",
        abstract: "Resume a paused session."
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
