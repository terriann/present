import Testing
import Foundation
@testable import PresentCore

@Suite("Validation Tests")
struct ValidationTests {

    // MARK: - sanitize()

    @Test func sanitizeTrimsWhitespace() throws {
        let result = try Validation.sanitize("  hello  ", fieldName: "test", maxLength: 100)
        #expect(result == "hello")
    }

    @Test func sanitizeEmptyStringThrows() {
        #expect(throws: PresentError.self) {
            try Validation.sanitize("", fieldName: "test", maxLength: 100)
        }
    }

    @Test func sanitizeWhitespaceOnlyThrows() {
        #expect(throws: PresentError.self) {
            try Validation.sanitize("   \n\t  ", fieldName: "test", maxLength: 100)
        }
    }

    @Test func sanitizeEmptyAllowedWhenFlagged() throws {
        let result = try Validation.sanitize("", fieldName: "test", maxLength: 100, allowEmpty: true)
        #expect(result == "")
    }

    @Test func sanitizeControlCharacterThrows() {
        #expect(throws: PresentError.self) {
            try Validation.sanitize("hello\u{0000}world", fieldName: "test", maxLength: 100)
        }
    }

    @Test func sanitizeBellCharacterThrows() {
        #expect(throws: PresentError.self) {
            try Validation.sanitize("test\u{0007}value", fieldName: "test", maxLength: 100)
        }
    }

    @Test func sanitizeTabAllowed() throws {
        let result = try Validation.sanitize("hello\tworld", fieldName: "test", maxLength: 100)
        #expect(result == "hello\tworld")
    }

    @Test func sanitizeNewlineAllowed() throws {
        let result = try Validation.sanitize("line1\nline2", fieldName: "test", maxLength: 100)
        #expect(result == "line1\nline2")
    }

    @Test func sanitizeCarriageReturnAllowed() throws {
        let result = try Validation.sanitize("line1\rline2", fieldName: "test", maxLength: 100)
        #expect(result == "line1\rline2")
    }

    @Test func sanitizeExceedsMaxLengthThrows() {
        #expect(throws: PresentError.self) {
            try Validation.sanitize(String(repeating: "a", count: 101), fieldName: "test", maxLength: 100)
        }
    }

    @Test func sanitizeExactMaxLengthSucceeds() throws {
        let value = String(repeating: "a", count: 100)
        let result = try Validation.sanitize(value, fieldName: "test", maxLength: 100)
        #expect(result == value)
    }

    @Test func sanitizeUnicodePreserved() throws {
        let result = try Validation.sanitize("café ☕ 日本語", fieldName: "test", maxLength: 100)
        #expect(result == "café ☕ 日本語")
    }

    @Test func sanitizeEmojiPreserved() throws {
        let result = try Validation.sanitize("🎯 Focus time", fieldName: "test", maxLength: 100)
        #expect(result == "🎯 Focus time")
    }

    // MARK: - sanitizeOptional()

    @Test func sanitizeOptionalNilReturnsNil() throws {
        let result = try Validation.sanitizeOptional(nil, fieldName: "test", maxLength: 100)
        #expect(result == nil)
    }

    @Test func sanitizeOptionalEmptyReturnsNil() throws {
        let result = try Validation.sanitizeOptional("", fieldName: "test", maxLength: 100)
        #expect(result == nil)
    }

    @Test func sanitizeOptionalWhitespaceOnlyReturnsNil() throws {
        let result = try Validation.sanitizeOptional("   ", fieldName: "test", maxLength: 100)
        #expect(result == nil)
    }

    @Test func sanitizeOptionalValidStringReturns() throws {
        let result = try Validation.sanitizeOptional("hello", fieldName: "test", maxLength: 100)
        #expect(result == "hello")
    }

    @Test func sanitizeOptionalControlCharsThrow() {
        #expect(throws: PresentError.self) {
            try Validation.sanitizeOptional("bad\u{0002}value", fieldName: "test", maxLength: 100)
        }
    }

    // MARK: - validateRange()

    @Test func validateRangeWithinBounds() throws {
        try Validation.validateRange(5, range: 1...10, fieldName: "test")
    }

    @Test func validateRangeLowerBoundary() throws {
        try Validation.validateRange(1, range: 1...10, fieldName: "test")
    }

    @Test func validateRangeUpperBoundary() throws {
        try Validation.validateRange(10, range: 1...10, fieldName: "test")
    }

    @Test func validateRangeBelowMinThrows() {
        #expect(throws: PresentError.self) {
            try Validation.validateRange(0, range: 1...10, fieldName: "test")
        }
    }

    @Test func validateRangeAboveMaxThrows() {
        #expect(throws: PresentError.self) {
            try Validation.validateRange(11, range: 1...10, fieldName: "test")
        }
    }

    // MARK: - validatePreferenceKey()

    @Test func validateKnownPreferenceKey() throws {
        let firstKey = try #require(Validation.knownPreferenceKeys.first)
        try Validation.validatePreferenceKey(firstKey)
    }

    @Test func validateUnknownPreferenceKeyThrows() {
        #expect(throws: PresentError.self) {
            try Validation.validatePreferenceKey("nonExistentKey12345")
        }
    }

    // MARK: - validateLink (accepted)

    @Test func acceptsHttpUrl() throws {
        try Validation.validateLink("http://example.com")
    }

    @Test func acceptsHttpsUrl() throws {
        try Validation.validateLink("https://example.com")
    }

    @Test func acceptsHttpsUrlWithPathAndQuery() throws {
        try Validation.validateLink("https://example.com/path?q=1")
    }

    @Test func acceptsUppercaseScheme() throws {
        try Validation.validateLink("HTTPS://example.com")
    }

    // MARK: - validateLink (rejected schemes)

    @Test func rejectsFileScheme() throws {
        #expect(throws: PresentError.self) {
            try Validation.validateLink("file:///etc/passwd")
        }
    }

    @Test func rejectsJavascriptScheme() throws {
        #expect(throws: PresentError.self) {
            try Validation.validateLink("javascript:alert(1)")
        }
    }

    @Test func rejectsDataScheme() throws {
        #expect(throws: PresentError.self) {
            try Validation.validateLink("data:text/html,<h1>")
        }
    }

    @Test func rejectsFtpScheme() throws {
        #expect(throws: PresentError.self) {
            try Validation.validateLink("ftp://files.example.com")
        }
    }

    // MARK: - validateLink (invalid URLs)

    @Test func rejectsEmptyString() throws {
        #expect(throws: PresentError.self) {
            try Validation.validateLink("")
        }
    }

    @Test func rejectsUrlWithoutScheme() throws {
        #expect(throws: PresentError.self) {
            try Validation.validateLink("example.com")
        }
    }

    @Test func rejectsUrlWithoutHost() throws {
        #expect(throws: PresentError.self) {
            try Validation.validateLink("https://")
        }
    }
}
