import Testing
@testable import PresentCLI

@Suite("CSV Escaping Tests")
struct CSVEscapingTests {

    // MARK: - Passthrough (no escaping needed)

    @Test func plainStringPassesThrough() {
        #expect(escapeCSVField("hello") == "hello")
    }

    @Test func emptyStringPassesThrough() {
        #expect(escapeCSVField("") == "")
    }

    @Test func numericStringPassesThrough() {
        #expect(escapeCSVField("12345") == "12345")
    }

    // MARK: - Comma handling

    @Test func fieldWithCommaIsQuoted() {
        #expect(escapeCSVField("one,two") == "\"one,two\"")
    }

    // MARK: - Double quote handling

    @Test func fieldWithDoubleQuoteIsDoubledAndQuoted() {
        #expect(escapeCSVField("say \"hello\"") == "\"say \"\"hello\"\"\"")
    }

    @Test func fieldWithOnlyQuotes() {
        // Input: "" (2 quotes) → doubled: """" (4 quotes) → wrapped: """""" (6 chars)
        #expect(escapeCSVField("\"\"") == "\"\"\"\"\"\"")
    }

    // MARK: - Newline handling

    @Test func fieldWithNewlineIsQuoted() {
        #expect(escapeCSVField("line1\nline2") == "\"line1\nline2\"")
    }

    @Test func fieldWithCarriageReturnIsQuoted() {
        #expect(escapeCSVField("line1\rline2") == "\"line1\rline2\"")
    }

    @Test func fieldWithCRLFIsQuoted() {
        let input = "line1\r\nline2"
        let expected = "\"\(input)\""
        #expect(escapeCSVField(input) == expected)
    }

    // MARK: - Combined special characters

    @Test func fieldWithCommaAndQuote() {
        #expect(escapeCSVField("a,\"b\"") == "\"a,\"\"b\"\"\"")
    }

    @Test func fieldWithAllSpecialCharacters() {
        let input = "comma,quote\"newline\nreturn\r"
        let expected = "\"comma,quote\"\"newline\nreturn\r\""
        #expect(escapeCSVField(input) == expected)
    }
}
