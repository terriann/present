import ArgumentParser
import Foundation
import PresentCore

struct ActivityUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update an activity."
    )

    @Argument(help: "Activity ID.")
    var id: Int64

    @Option(name: .long, help: "New title.")
    var title: String?

    @Option(name: .long, help: "Link URL.")
    var link: String?

    @Option(name: .long, help: "External ID.")
    var externalId: String?

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()

        guard title != nil || link != nil || externalId != nil else {
            print("Provide at least one field to update (--title, --link, --external-id).")
            throw ExitCode.failure
        }

        let service = try CLIServiceFactory.makeService()
        let input = UpdateActivityInput(title: title, externalId: externalId, link: link)
        let activity = try await service.updateActivity(id: id, input)
        let tags = try await service.tagsForActivity(activityId: id)

        switch outputOptions.format {
        case .json:
            try outputOptions.printJSON(activity.toJSONDict(tags: tags))

        case .text:
            if try outputOptions.printTextField(activity.toTextFields(tags: tags)) { break }
            print("Updated activity: \(activity.title) [\(activity.id!)]")

        case .csv:
            print("CSV output not supported for activity update.")
            throw ExitCode.failure
        }

        IPCClient().send(.dataChanged)
    }
}
