import Testing
@testable import PresentCLI
@testable import PresentCore

@Suite("SessionType Parsing Tests")
struct SessionTypeParsingTests {

    @Test func validWorkType() throws {
        let type = try SessionType.parseOrFail("work")
        #expect(type == .work)
    }

    @Test func validRhythmType() throws {
        let type = try SessionType.parseOrFail("rhythm")
        #expect(type == .rhythm)
    }

    @Test func validTimeboundType() throws {
        let type = try SessionType.parseOrFail("timebound")
        #expect(type == .timebound)
    }

    @Test func invalidTypeThrows() {
        #expect(throws: (any Error).self) {
            try SessionType.parseOrFail("invalid")
        }
    }

    @Test func emptyStringThrows() {
        #expect(throws: (any Error).self) {
            try SessionType.parseOrFail("")
        }
    }

    @Test func caseSensitive() {
        #expect(throws: (any Error).self) {
            try SessionType.parseOrFail("Work")
        }
    }
}
