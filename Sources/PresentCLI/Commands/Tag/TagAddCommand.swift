import ArgumentParser
import Foundation
import PresentCore

struct TagAddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a new tag."
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
            print("Added tag: \(tag.name) [\(tag.id!)]")

        case .csv:
            print("CSV output not supported for tag add.")
            throw ExitCode.failure
        }

        IPCClient().send(.dataChanged)
    }
}
