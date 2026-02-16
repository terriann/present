import ArgumentParser
import Foundation
import PresentCore

struct ConfigListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all preferences."
    )

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        let prefs = try await service.listPreferences()

        switch outputOptions.format {
        case .json:
            let items: [[String: Any]] = prefs.map { pref in
                ["key": pref.key, "value": pref.value]
            }
            try outputOptions.printJSONArray(items)

        case .text:
            if outputOptions.field != nil {
                print("--field is not supported for list output.")
                throw ExitCode.failure
            }

            if prefs.isEmpty {
                print("No preferences set.")
                return
            }

            let maxKeyLen = prefs.map(\.key.count).max() ?? 0
            for pref in prefs {
                let padded = pref.key.padding(toLength: maxKeyLen, withPad: " ", startingAt: 0)
                print("  \(padded) = \(pref.value)")
            }

        case .csv:
            print("Key,Value")
            for pref in prefs {
                let escapedValue = pref.value.contains(",") ? "\"\(pref.value)\"" : pref.value
                print("\(pref.key),\(escapedValue)")
            }
        }
    }
}
