import ArgumentParser
import Foundation

enum OutputFormat: String, ExpressibleByArgument, CaseIterable, Sendable {
    case json    // Structured, scriptable (default)
    case text    // Human-readable
    case csv     // Tabular data only
}

struct OutputOptions: ParsableArguments {
    @Option(name: [.customShort("f"), .customLong("format")], help: "Output format: json, text, csv.")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Extract a single field value from the response.")
    var field: String?
}

// MARK: - Output Helpers

extension OutputOptions {

    /// Validates option compatibility. Call at the start of run().
    func validateOptions() throws {
        if field != nil && format == .csv {
            printError("--field is not supported with CSV output.")
            throw ExitCode.failure
        }
    }

    /// Prints a JSON dictionary, handling --field extraction.
    func printJSON(_ dict: [String: Any]) throws {
        if let fieldName = field {
            guard let value = dict[fieldName] else {
                throw ExitCode.failure
            }
            printRawValue(value)
            return
        }
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }

    /// Prints a JSON array. --field is not supported for bare arrays.
    func printJSONArray(_ array: Any) throws {
        if field != nil {
            printError("--field is not supported for list output.")
            throw ExitCode.failure
        }
        let data = try JSONSerialization.data(withJSONObject: array, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }

    /// For text output with --field: prints the formatted value and returns true.
    /// Returns false if --field is not set (caller should print full text output).
    /// Throws ExitCode.failure if the field key is not found.
    func printTextField(_ fields: [String: String]) throws -> Bool {
        guard let fieldName = field else { return false }
        guard let value = fields[fieldName] else {
            throw ExitCode.failure
        }
        print(value)
        return true
    }

    // MARK: - Private

    private func printRawValue(_ value: Any) {
        switch value {
        case let str as String:
            print(str)
        case let bool as Bool:
            print(bool)
        case let num as any Numeric & CustomStringConvertible:
            print(num)
        case is NSNull:
            print("null")
        default:
            // Nested object/array — print as JSON
            if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        }
    }

    private func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
