import Testing
@testable import PresentCore

@Suite("Validation Tests")
struct ValidationTests {

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
