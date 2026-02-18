import ArgumentParser
import Foundation
import PresentCore

struct ActivityNoteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "note",
        abstract: "Append a note to an activity.",
        discussion: """
            Appends text to an activity's notes field. If no --id is given, \
            the note is added to the currently running session's activity.

            ## Examples

            # Add a note to the current session's activity
            $ present-cli activity note "Completed the first draft"

            # Add a note to a specific activity by ID
            $ present-cli activity note "Follow up needed" --id 3

            # Add a note and show the updated activity
            $ present-cli activity note "Bug found in auth flow" -f text
            """
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
