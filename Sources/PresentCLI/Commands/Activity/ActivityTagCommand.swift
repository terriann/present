import ArgumentParser
import Foundation
import PresentCore

struct ActivityTagCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tag",
        abstract: "Add a tag to an activity.",
        discussion: """
            Associates an existing tag with an activity. Use `tag list` to \
            find available tag IDs, or `tag add` to create a new tag first.

            ## Examples

            # Tag activity 1 with tag 2
            $ present-cli activity tag 1 2

            # Tag and show result as text
            $ present-cli activity tag 1 2 -f text
            """
    )

    @Argument(help: "Activity ID.")
    var activityId: Int64

    @Argument(help: "Tag ID.")
    var tagId: Int64

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        try await service.tagActivity(activityId: activityId, tagId: tagId)

        let activity = try await service.getActivity(id: activityId)
        let tag = try await service.getTag(id: tagId)

        switch outputOptions.format {
        case .json:
            let dict: [String: Any] = [
                "activity": activity.toNestedJSONDict(),
                "tag": tag.toNestedJSONDict(),
            ]
            try outputOptions.printJSON(dict)

        case .text:
            let textFields: [String: String] = [
                "activityId": "\(activityId)",
                "activity": activity.title,
                "tagId": "\(tagId)",
                "tag": tag.name,
            ]
            if try outputOptions.printTextField(textFields) { break }
            print("Tagged \"\(activity.title)\" with \(tag.name)")

        case .csv:
            print("CSV output not supported for activity tag.")
            throw ExitCode.failure
        }

        IPCClient().send(.dataChanged)
    }
}
