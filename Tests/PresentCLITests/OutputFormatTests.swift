import Testing
import ArgumentParser
@testable import PresentCLI

@Suite("OutputFormat Tests")
struct OutputFormatTests {

    // MARK: - OutputFormat enum

    @Test func allCasesIncludesThreeFormats() {
        #expect(OutputFormat.allCases.count == 3)
        #expect(OutputFormat.allCases.contains(.json))
        #expect(OutputFormat.allCases.contains(.text))
        #expect(OutputFormat.allCases.contains(.csv))
    }

    @Test func rawValuesMatchExpected() {
        #expect(OutputFormat.json.rawValue == "json")
        #expect(OutputFormat.text.rawValue == "text")
        #expect(OutputFormat.csv.rawValue == "csv")
    }

    // MARK: - validateOptions()

    @Test func validateOptionsPassesForJsonWithoutField() throws {
        let options = try OutputOptions.parse(["-f", "json"])
        try options.validateOptions()
    }

    @Test func validateOptionsPassesForTextWithField() throws {
        let options = try OutputOptions.parse(["-f", "text", "--field", "id"])
        try options.validateOptions()
    }

    @Test func validateOptionsThrowsForCSVWithField() throws {
        let options = try OutputOptions.parse(["-f", "csv", "--field", "id"])
        #expect(throws: ExitCode.self) {
            try options.validateOptions()
        }
    }

    @Test func validateOptionsPassesForCSVWithoutField() throws {
        let options = try OutputOptions.parse(["-f", "csv"])
        try options.validateOptions()
    }

    // MARK: - throwCSVNotSupported()

    @Test func throwCSVNotSupportedThrows() throws {
        let options = try OutputOptions.parse(["-f", "csv"])
        #expect(throws: ExitCode.self) {
            try options.throwCSVNotSupported(for: "test command")
        }
    }

    // MARK: - printJSON field extraction

    @Test func printJSONThrowsForMissingField() throws {
        let options = try OutputOptions.parse(["--field", "nonexistent"])
        #expect(throws: ExitCode.self) {
            try options.printJSON(["id": 1, "name": "test"])
        }
    }

    @Test func printJSONSucceedsForExistingField() throws {
        let options = try OutputOptions.parse(["--field", "id"])
        // Should not throw — prints to stdout
        try options.printJSON(["id": 1, "name": "test"])
    }

    // MARK: - printJSONArray field validation

    @Test func printJSONArrayThrowsWithField() throws {
        let options = try OutputOptions.parse(["--field", "id"])
        #expect(throws: ExitCode.self) {
            try options.printJSONArray([1, 2, 3])
        }
    }

    @Test func printJSONArraySucceedsWithoutField() throws {
        let options = try OutputOptions.parse([])
        try options.printJSONArray([1, 2, 3])
    }

    // MARK: - printTextField

    @Test func printTextFieldReturnsFalseWithoutField() throws {
        let options = try OutputOptions.parse([])
        let result = try options.printTextField(["id": "1"])
        #expect(result == false)
    }

    @Test func printTextFieldReturnsTrueForExistingField() throws {
        let options = try OutputOptions.parse(["--field", "id"])
        let result = try options.printTextField(["id": "1", "name": "test"])
        #expect(result == true)
    }

    @Test func printTextFieldThrowsForMissingField() throws {
        let options = try OutputOptions.parse(["--field", "nonexistent"])
        #expect(throws: ExitCode.self) {
            try options.printTextField(["id": "1"])
        }
    }

    // MARK: - Default format

    @Test func defaultFormatIsJSON() throws {
        let options = try OutputOptions.parse([])
        #expect(options.format == .json)
    }
}
