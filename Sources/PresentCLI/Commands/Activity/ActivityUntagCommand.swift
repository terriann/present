import ArgumentParser
import Foundation
import PresentCore

struct ActivityUntagCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "untag",
        abstract: "Remove a tag from an activity."
    )

    @Argument(help: "Activity ID.")
    var activityId: Int64

    @Argument(help: "Tag ID.")
    var tagId: Int64

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        let activity = try await service.getActivity(id: activityId)
        let tag = try await service.getTag(id: tagId)

        try await service.untagActivity(activityId: activityId, tagId: tagId)

        switch outputOptions.format {
        case .json:
            let dict: [String: Any] = [
                "activity": activity.toNestedJSONDict(),
                "tag": tag.toNestedJSONDict(),
                "removed": true,
            ]
            try outputOptions.printJSON(dict)

        case .text:
            let textFields: [String: String] = [
                "activityId": "\(activityId)",
                "activity": activity.title,
                "tagId": "\(tagId)",
                "tag": tag.name,
                "removed": "true",
            ]
            if try outputOptions.printTextField(textFields) { break }
            print("Removed \(tag.name) from \"\(activity.title)\"")

        case .csv:
            print("CSV output not supported for activity untag.")
            throw ExitCode.failure
        }

        IPCClient().send(.dataChanged)
    }
}
