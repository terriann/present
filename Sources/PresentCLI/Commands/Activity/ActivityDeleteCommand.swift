import ArgumentParser
import Foundation
import PresentCore

struct ActivityDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete an activity and its sessions.",
        discussion: """
            Permanently deletes an activity and all of its associated sessions. \
            This action cannot be undone.

            ## Examples

            # Delete an activity
            $ present-cli activity delete 5

            # Delete and confirm via text output
            $ present-cli activity delete 5 -f text
            """
    )

    @Argument(help: "Activity ID to delete.")
    var id: Int64

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        let activity = try await service.getActivity(id: id)
        let tags = try await service.tagsForActivity(activityId: id)
        try await service.deleteActivity(id: id)

        switch outputOptions.format {
        case .json:
            var dict = activity.toJSONDict(tags: tags)
            dict["deleted"] = true
            try outputOptions.printJSON(dict)

        case .text:
            var textFields = activity.toTextFields(tags: tags)
            textFields["deleted"] = "true"
            if try outputOptions.printTextField(textFields) { break }
            print("Deleted \"\(activity.title)\"")

        case .csv:
            try outputOptions.throwCSVNotSupported(for: "activity delete")
        }

        IPCClient().send(.dataChanged)
    }
}
