import ArgumentParser
import Foundation
import PresentCore

struct ActivityAddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a new activity."
    )

    @Argument(help: "Activity name.")
    var name: String

    @Option(name: .long, help: "Link URL for the activity.")
    var link: String?

    @Option(name: .long, help: "External ID for the activity.")
    var externalId: String?

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        let activity = try await service.createActivity(
            CreateActivityInput(title: name, externalId: externalId, link: link)
        )

        // New activity has no tags yet
        switch outputOptions.format {
        case .json:
            try outputOptions.printJSON(activity.toJSONDict(tags: []))

        case .text:
            if try outputOptions.printTextField(activity.toTextFields(tags: [])) { break }
            print("Added activity: \(activity.title) [\(activity.id!)]")

        case .csv:
            print("CSV output not supported for activity add.")
            throw ExitCode.failure
        }

        IPCClient().send(.dataChanged)
    }
}
