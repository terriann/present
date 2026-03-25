import ArgumentParser
import Foundation
import PresentCore

struct TagGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Show tag details.",
        discussion: """
            Retrieves details for a specific tag by its ID.

            ## Examples

            # Get tag details
            $ present-cli tag get 1

            # Get just the tag name
            $ present-cli tag get 1 --field name
            """
    )

    @Argument(help: "Tag ID.")
    var id: Int64

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        let tag = try await service.getTag(id: id)

        switch outputOptions.format {
        case .json:
            try outputOptions.printJSON(tag.toJSONDict())

        case .text:
            if try outputOptions.printTextField(tag.toTextFields()) { break }
            print("[\(tag.id ?? 0)] \(tag.name)")

        case .csv:
            try outputOptions.throwCSVNotSupported(for: "tag get")
        }
    }
}
