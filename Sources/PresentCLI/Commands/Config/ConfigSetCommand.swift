import ArgumentParser
import Foundation
import PresentCore

struct ConfigSetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set a preference value.",
        discussion: """
            Sets a preference to the given value. Only known preference keys \
            are accepted. If the app is running, the change is synced \
            automatically via IPC.

            ## Examples

            # Set the week start day
            $ present-cli config set weekStartDay 2

            # Enable sound effects
            $ present-cli config set soundEffectsEnabled true

            # Set and confirm
            $ present-cli config set weekStartDay 2 -f text
            """
    )

    @Argument(help: "Preference key.")
    var key: String

    @Argument(help: "Preference value.")
    var value: String

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()

        // Warn on unknown keys (service will reject them)
        if !Validation.knownPreferenceKeys.contains(key) {
            let known = Validation.knownPreferenceKeys.sorted().joined(separator: ", ")
            print("Unknown preference key: \(key). Known keys: \(known)")
            throw ExitCode.failure
        }

        let service = try CLIServiceFactory.makeService()
        try await service.setPreference(key: key, value: value)

        switch outputOptions.format {
        case .json:
            let dict: [String: Any] = ["key": key, "value": value]
            try outputOptions.printJSON(dict)

        case .text:
            let textFields: [String: String] = ["key": key, "value": value]
            if try outputOptions.printTextField(textFields) { break }
            print("Set \(key) = \(value)")

        case .csv:
            try outputOptions.throwCSVNotSupported(for: "config set")
        }

        IPCClient().send(.dataChanged)
    }
}
