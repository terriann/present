import ArgumentParser
import Foundation
import PresentCore

struct TagUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Rename a tag."
    )

    @Argument(help: "Tag ID.")
    var id: Int64

    @Option(name: .long, help: "New tag name.")
    var name: String

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        let tag = try await service.updateTag(id: id, name: name)

        switch outputOptions.format {
        case .json:
            try outputOptions.printJSON(tag.toJSONDict())

        case .text:
            if try outputOptions.printTextField(tag.toTextFields()) { break }
            print("Updated tag: \(tag.name) [\(tag.id!)]")

        case .csv:
            print("CSV output not supported for tag update.")
            throw ExitCode.failure
        }

        IPCClient().send(.dataChanged)
    }
}
