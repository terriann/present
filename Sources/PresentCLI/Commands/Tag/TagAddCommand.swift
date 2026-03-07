import ArgumentParser
import Foundation
import PresentCore

struct TagAddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a new tag.",
        discussion: """
            Creates a new tag with the given name. Tags can then be attached \
            to activities using `activity tag`.

            ## Examples

            # Create a tag
            $ present-cli tag add "client-work"

            # Create a tag and get its ID
            $ present-cli tag add "urgent" --field id
            """
    )

    @Argument(help: "Tag name.")
    var name: String

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        let tag = try await service.createTag(name: name)

        switch outputOptions.format {
        case .json:
            try outputOptions.printJSON(tag.toJSONDict())

        case .text:
            if try outputOptions.printTextField(tag.toTextFields()) { break }
            print("Added tag: \(tag.name) [\(tag.id ?? 0)]")

        case .csv:
            print("CSV output not supported for tag add.")
            throw ExitCode.failure
        }

        IPCClient().send(.dataChanged)
    }
}
