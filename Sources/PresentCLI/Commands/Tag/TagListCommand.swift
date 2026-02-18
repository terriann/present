import ArgumentParser
import Foundation
import PresentCore

struct TagListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all tags.",
        discussion: """
            Lists all tags in the system.

            ## Examples

            # List all tags as JSON (default)
            $ present-cli tag list

            # List as text
            $ present-cli tag list -f text

            # Export as CSV
            $ present-cli tag list -f csv
            """
    )

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        let tags = try await service.listTags()

        switch outputOptions.format {
        case .json:
            try outputOptions.printJSONArray(tags.map { $0.toJSONDict() })

        case .text:
            if outputOptions.field != nil {
                print("--field is not supported for list output.")
                throw ExitCode.failure
            }

            if tags.isEmpty {
                print("No tags found.")
                return
            }

            for tag in tags {
                print("  [\(tag.id!)] \(tag.name)")
            }

        case .csv:
            print("ID,Name")
            for tag in tags {
                let escapedName = tag.name.contains(",") ? "\"\(tag.name)\"" : tag.name
                print("\(tag.id!),\(escapedName)")
            }
        }
    }
}
