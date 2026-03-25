import ArgumentParser
import Foundation
import PresentCore

struct ActivityAddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a new activity.",
        discussion: """
            Creates a new activity with the given name. Optionally attach a \
            link URL and external ID for integration with other tools.

            ## Examples

            # Add a simple activity
            $ present-cli activity add "My Project"

            # Add with a link and external ID
            $ present-cli activity add "Client Work" --link "https://example.com" --external-id "PROJ-123"

            # Add and get just the new ID
            $ present-cli activity add "Reading" --field id
            """
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
            print("Added activity: \(activity.title) [\(activity.id ?? 0)]")

        case .csv:
            try outputOptions.throwCSVNotSupported(for: "activity add")
        }

        IPCClient().send(.dataChanged)
    }
}
