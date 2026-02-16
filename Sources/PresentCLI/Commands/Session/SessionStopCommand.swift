import ArgumentParser
import Foundation
import PresentCore

struct SessionStopCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop the current session."
    )

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        let session = try await service.stopSession()
        let activity = try await service.getActivity(id: session.activityId)

        switch outputOptions.format {
        case .json:
            try outputOptions.printJSON(session.toJSONDict(activity: activity))

        case .text:
            let textFields = session.toTextFields(activity: activity)
            if try outputOptions.printTextField(textFields) { break }

            print("Stopped session for \"\(activity.title)\"")
            if let duration = session.durationSeconds {
                print("Duration: \(TimeFormatting.formatDuration(seconds: duration))")
            }

        case .csv:
            print("CSV output not supported for session stop.")
            throw ExitCode.failure
        }

        IPCClient().send(.sessionStopped)
    }
}
