import ArgumentParser
import Foundation
import PresentCore

struct SessionGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Show session details."
    )

    @Argument(help: "Session ID.")
    var id: Int64

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        let (session, activity) = try await service.getSession(id: id)

        switch outputOptions.format {
        case .json:
            try outputOptions.printJSON(session.toJSONDict(activity: activity))

        case .text:
            let textFields = session.toTextFields(activity: activity)
            if try outputOptions.printTextField(textFields) { break }

            let dateStr = TimeFormatting.formatDate(session.startedAt)
            let timeStr = TimeFormatting.formatTime(session.startedAt)
            let typeLabel = SessionTypeConfig.config(for: session.sessionType).displayName
            print("[\(session.id!)] \(dateStr) \(timeStr) — \(activity.title) (\(typeLabel))")
            print("State: \(session.state.rawValue)")
            if let duration = session.durationSeconds {
                print("Duration: \(TimeFormatting.formatDuration(seconds: duration))")
            }

        case .csv:
            print("CSV output not supported for session get.")
            throw ExitCode.failure
        }
    }
}
