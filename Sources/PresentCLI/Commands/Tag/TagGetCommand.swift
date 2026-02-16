import ArgumentParser
import Foundation
import PresentCore

struct TagGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Show tag details."
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
            print("[\(tag.id!)] \(tag.name)")

        case .csv:
            print("CSV output not supported for tag get.")
            throw ExitCode.failure
        }
    }
}
