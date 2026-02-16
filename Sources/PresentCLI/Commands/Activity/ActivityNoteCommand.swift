import ArgumentParser
import Foundation
import PresentCore

struct ActivityNoteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "note",
        abstract: "Append a note to an activity."
    )

    @Argument(help: "Text to append to the activity's notes.")
    var text: String

    @Option(name: .long, help: "Activity ID (defaults to current session's activity).")
    var id: Int64?

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()

        let activityId: Int64
        let activityTitle: String

        if let explicitId = id {
            let activity = try await service.getActivity(id: explicitId)
            activityId = activity.id!
            activityTitle = activity.title
        } else {
            guard let (session, activity) = try await service.currentSession() else {
                print("No active session. Use --id to specify an activity.")
                throw ExitCode.failure
            }
            activityId = session.activityId
            activityTitle = activity.title
        }

        let updated = try await service.appendNote(activityId: activityId, text: text)
        let tags = try await service.tagsForActivity(activityId: activityId)

        switch outputOptions.format {
        case .json:
            try outputOptions.printJSON(updated.toJSONDict(tags: tags))

        case .text:
            if try outputOptions.printTextField(updated.toTextFields(tags: tags)) { break }
            print("Note appended to \"\(activityTitle)\"")

        case .csv:
            print("CSV output not supported for activity note.")
            throw ExitCode.failure
        }

        IPCClient().send(.activityUpdated)
    }
}
