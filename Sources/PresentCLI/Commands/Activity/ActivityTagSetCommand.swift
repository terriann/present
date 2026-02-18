import ArgumentParser
import Foundation
import PresentCore

struct ActivityTagSetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Replace all tags on an activity.",
        discussion: """
            Atomically replaces all tags on an activity with the specified \
            set. Pass zero or more tag IDs to set the exact tag list.

            ## Examples

            # Set activity 1 to have tags 2 and 3
            $ present-cli activity tag set 1 2 3

            # Remove all tags from activity 1
            $ present-cli activity tag set 1

            # Set tags and show result as text
            $ present-cli activity tag set 1 2 3 -f text
            """
    )

    @Argument(help: "Activity ID.")
    var activityId: Int64

    @Argument(parsing: .remaining, help: "Tag IDs to set.")
    var tagIds: [Int64] = []

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        let tags = try await service.setActivityTags(activityId: activityId, tagIds: tagIds)
        let activity = try await service.getActivity(id: activityId)

        switch outputOptions.format {
        case .json:
            let dict: [String: Any] = [
                "activity": activity.toNestedJSONDict(),
                "tags": tags.map { $0.toJSONDict() },
            ]
            try outputOptions.printJSON(dict)

        case .text:
            let tagNames = tags.map(\.name).joined(separator: ", ")
            let textFields: [String: String] = [
                "activityId": "\(activityId)",
                "activity": activity.title,
                "tags": tagNames.isEmpty ? "(none)" : tagNames,
                "tagCount": "\(tags.count)",
            ]
            if try outputOptions.printTextField(textFields) { break }

            if tags.isEmpty {
                print("Removed all tags from \"\(activity.title)\"")
            } else {
                print("Set tags on \"\(activity.title)\": \(tagNames)")
            }

        case .csv:
            print("CSV output not supported for activity tag set.")
            throw ExitCode.failure
        }

        IPCClient().send(.dataChanged)
    }
}
