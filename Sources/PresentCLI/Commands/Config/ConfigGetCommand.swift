import ArgumentParser
import Foundation
import PresentCore

struct ConfigGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Get a preference value.",
        discussion: """
            Gets the current value of a specific preference key. Returns \
            null if the preference has not been set.

            ## Examples

            # Get a preference value
            $ present-cli config get weekStartDay

            # Get just the value for scripting
            $ present-cli config get weekStartDay --field value
            """
    )

    @Argument(help: "Preference key.")
    var key: String

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        let value = try await service.getPreference(key: key)

        switch outputOptions.format {
        case .json:
            var dict: [String: Any] = ["key": key]
            if let value {
                dict["value"] = value
            } else {
                dict["value"] = NSNull()
            }
            try outputOptions.printJSON(dict)

        case .text:
            let textFields: [String: String] = [
                "key": key,
                "value": value ?? "",
            ]
            if try outputOptions.printTextField(textFields) { break }

            if let value {
                print("\(key) = \(value)")
            } else {
                print("\(key) is not set.")
            }

        case .csv:
            print("CSV output not supported for config get.")
            throw ExitCode.failure
        }
    }
}
