import ArgumentParser
import Foundation
import PresentCore

struct ActivityUnarchiveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unarchive",
        abstract: "Unarchive an activity.",
        discussion: """
            Restores an archived activity back to the active list.

            ## Examples

            # Unarchive an activity
            $ present-cli activity unarchive 3

            # Unarchive and show details
            $ present-cli activity unarchive 3 -f text
            """
    )

    @Argument(help: "Activity ID to unarchive.")
    var id: Int64

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        let activity = try await service.unarchiveActivity(id: id)
        let tags = try await service.tagsForActivity(activityId: id)

        switch outputOptions.format {
        case .json:
            try outputOptions.printJSON(activity.toJSONDict(tags: tags))

        case .text:
            if try outputOptions.printTextField(activity.toTextFields(tags: tags)) { break }
            print("Unarchived \"\(activity.title)\"")

        case .csv:
            try outputOptions.throwCSVNotSupported(for: "activity unarchive")
        }

        IPCClient().send(.dataChanged)
    }
}
