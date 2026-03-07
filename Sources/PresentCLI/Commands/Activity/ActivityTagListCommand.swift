import ArgumentParser
import Foundation
import PresentCore

struct ActivityTagListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List tags on an activity.",
        discussion: """
            Shows all tags currently associated with an activity.

            ## Examples

            # List tags on activity 1
            $ present-cli activity tag list 1

            # List in text format
            $ present-cli activity tag list 1 -f text
            """
    )

    @Argument(help: "Activity ID.")
    var activityId: Int64

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()

        // Validate activity exists
        let activity = try await service.getActivity(id: activityId)
        let tags = try await service.tagsForActivity(activityId: activityId)

        switch outputOptions.format {
        case .json:
            let dict: [String: Any] = [
                "activity": activity.toNestedJSONDict(),
                "tags": tags.map { $0.toJSONDict() },
            ]
            try outputOptions.printJSON(dict)

        case .text:
            if outputOptions.field != nil {
                let textFields: [String: String] = [
                    "activityId": "\(activityId)",
                    "activity": activity.title,
                    "tags": tags.map(\.name).joined(separator: ", "),
                    "tagCount": "\(tags.count)",
                ]
                if try outputOptions.printTextField(textFields) { break }
            }

            if tags.isEmpty {
                print("No tags on \"\(activity.title)\"")
                return
            }

            print("Tags on \"\(activity.title)\":")
            for tag in tags {
                print("  [\(tag.id ?? 0)] \(tag.name)")
            }

        case .csv:
            print("Tag ID,Name")
            for tag in tags {
                let escapedName = tag.name.contains(",") ? "\"\(tag.name)\"" : tag.name
                print("\(tag.id ?? 0),\(escapedName)")
            }
        }
    }
}
