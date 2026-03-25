import Testing
import Foundation
@testable import PresentCLI

@Suite("DateParsing Tests")
struct DateParsingTests {

    // MARK: - parseDateOrFail

    @Test func validDateParses() throws {
        let date = try DateParsing.parseDateOrFail("2026-03-15", label: "--after")
        let cal = Calendar.current
        #expect(cal.component(.year, from: date) == 2026)
        #expect(cal.component(.month, from: date) == 3)
        #expect(cal.component(.day, from: date) == 15)
    }

    @Test func invalidDateThrows() {
        #expect(throws: (any Error).self) {
            try DateParsing.parseDateOrFail("not-a-date", label: "--after")
        }
    }

    @Test func partialDateThrows() {
        #expect(throws: (any Error).self) {
            try DateParsing.parseDateOrFail("2026-01", label: "--after")
        }
    }

    @Test func emptyStringDateThrows() {
        #expect(throws: (any Error).self) {
            try DateParsing.parseDateOrFail("", label: "--after")
        }
    }

    // MARK: - parseDateTime

    @Test func standardISO8601Parses() {
        let date = DateParsing.parseDateTime("2026-03-15T09:30:00Z")
        #expect(date != nil)
    }

    @Test func fractionalSecondsISO8601Parses() {
        let date = DateParsing.parseDateTime("2026-03-15T09:30:00.123Z")
        #expect(date != nil)
    }

    @Test func localDateTimeParsesWithoutTimezone() {
        let date = DateParsing.parseDateTime("2026-03-15T09:30:00")
        #expect(date != nil)
    }

    @Test func invalidDateTimeReturnsNil() {
        #expect(DateParsing.parseDateTime("not-a-date") == nil)
    }

    @Test func emptyStringDateTimeReturnsNil() {
        #expect(DateParsing.parseDateTime("") == nil)
    }

    @Test func dateOnlyStringDateTimeReturnsNil() {
        #expect(DateParsing.parseDateTime("2026-03-15") == nil)
    }

    // MARK: - parseDateTimeOrFail

    @Test func validDateTimeOrFailSucceeds() throws {
        let date = try DateParsing.parseDateTimeOrFail("2026-03-15T09:30:00Z", label: "start time")
        #expect(date != Date.distantPast)
    }

    @Test func invalidDateTimeOrFailThrows() {
        #expect(throws: (any Error).self) {
            try DateParsing.parseDateTimeOrFail("bad", label: "start time")
        }
    }
}
