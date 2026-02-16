import ArgumentParser
import Foundation
import PresentCore

struct ActivityArchiveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "archive",
        abstract: "Archive an activity."
    )

    @Argument(help: "Activity ID to archive.")
    var id: Int64

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        let result = try await service.archiveActivity(id: id)
        let activity = try await service.getActivity(id: id)
        let tags = try await service.tagsForActivity(activityId: id)

        switch outputOptions.format {
        case .json:
            var dict = activity.toJSONDict(tags: tags)
            switch result {
            case .archived:
                dict["result"] = "archived"
            case .promptDelete(let totalSeconds):
                dict["result"] = "promptDelete"
                dict["totalSeconds"] = totalSeconds
            }
            try outputOptions.printJSON(dict)

        case .text:
            var textFields = activity.toTextFields(tags: tags)
            switch result {
            case .archived:
                textFields["result"] = "archived"
            case .promptDelete(let totalSeconds):
                textFields["result"] = "promptDelete"
                textFields["totalSeconds"] = "\(totalSeconds)"
            }
            if try outputOptions.printTextField(textFields) { break }

            switch result {
            case .archived:
                print("Archived \"\(activity.title)\"")
            case .promptDelete(let totalSeconds):
                let duration = TimeFormatting.formatDuration(seconds: totalSeconds)
                print("\"\(activity.title)\" has only \(duration) tracked. Consider deleting instead.")
                print("To delete, use: present-cli activity delete \(id)")
            }

        case .csv:
            print("CSV output not supported for activity archive.")
            throw ExitCode.failure
        }

        IPCClient().send(.dataChanged)
    }
}
