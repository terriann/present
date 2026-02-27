import Testing
@testable import PresentCore

@Suite("TicketExtractor Tests")
struct TicketExtractorTests {

    // MARK: - Linear

    @Test func linearStandardUrl() {
        let result = TicketExtractor.extractTicketId(from: "https://linear.app/team/issue/LIN-123")
        #expect(result == "LIN-123")
    }

    @Test func linearDifferentTeamAndPrefix() {
        let result = TicketExtractor.extractTicketId(from: "https://linear.app/myteam/issue/FEAT-42")
        #expect(result == "FEAT-42")
    }

    @Test func linearUrlWithTrailingSlash() {
        let result = TicketExtractor.extractTicketId(from: "https://linear.app/team/issue/LIN-123/")
        #expect(result == "LIN-123")
    }

    @Test func linearUrlWithQueryParams() {
        let result = TicketExtractor.extractTicketId(from: "https://linear.app/team/issue/LIN-123?foo=bar")
        #expect(result == "LIN-123")
    }

    @Test func linearUrlWithNoIssueId() {
        let result = TicketExtractor.extractTicketId(from: "https://linear.app/team/issue/")
        #expect(result == nil)
    }

    // MARK: - Jira

    @Test func jiraStandardUrl() {
        let result = TicketExtractor.extractTicketId(from: "https://myorg.atlassian.net/browse/PROJ-123")
        #expect(result == "PROJ-123")
    }

    @Test func jiraDifferentOrgAndPrefix() {
        let result = TicketExtractor.extractTicketId(from: "https://company.atlassian.net/browse/ABC-1")
        #expect(result == "ABC-1")
    }

    @Test func jiraUrlWithTrailingSlash() {
        let result = TicketExtractor.extractTicketId(from: "https://myorg.atlassian.net/browse/PROJ-123/")
        #expect(result == "PROJ-123")
    }

    @Test func jiraUrlWithQueryParams() {
        let result = TicketExtractor.extractTicketId(from: "https://myorg.atlassian.net/browse/PROJ-123?filter=open")
        #expect(result == "PROJ-123")
    }

    @Test func jiraUrlWithNoBrowsePath() {
        let result = TicketExtractor.extractTicketId(from: "https://myorg.atlassian.net/projects/PROJ")
        #expect(result == nil)
    }

    // MARK: - GitHub

    @Test func githubStandardUrl() {
        let result = TicketExtractor.extractTicketId(from: "https://github.com/org/repo/issues/123")
        #expect(result == "org/repo#123")
    }

    @Test func githubRealWorldUrl() {
        let result = TicketExtractor.extractTicketId(from: "https://github.com/apple/swift/issues/42")
        #expect(result == "apple/swift#42")
    }

    @Test func githubUrlWithTrailingSlash() {
        let result = TicketExtractor.extractTicketId(from: "https://github.com/org/repo/issues/123/")
        #expect(result == "org/repo#123")
    }

    @Test func githubUrlWithQueryParams() {
        let result = TicketExtractor.extractTicketId(from: "https://github.com/org/repo/issues/123?comments=true")
        #expect(result == "org/repo#123")
    }

    @Test func githubUrlWithNoIssueNumber() {
        let result = TicketExtractor.extractTicketId(from: "https://github.com/org/repo/issues/")
        #expect(result == nil)
    }

    @Test func githubUrlNotAnIssue() {
        let result = TicketExtractor.extractTicketId(from: "https://github.com/org/repo/pulls/123")
        #expect(result == nil)
    }

    // MARK: - GitLab

    @Test func gitlabStandardUrl() {
        let result = TicketExtractor.extractTicketId(from: "https://gitlab.com/org/repo/-/issues/456")
        #expect(result == "org/repo#456")
    }

    @Test func gitlabUrlWithTrailingSlash() {
        let result = TicketExtractor.extractTicketId(from: "https://gitlab.com/org/repo/-/issues/456/")
        #expect(result == "org/repo#456")
    }

    @Test func gitlabUrlWithQueryParams() {
        let result = TicketExtractor.extractTicketId(from: "https://gitlab.com/org/repo/-/issues/456?view=all")
        #expect(result == "org/repo#456")
    }

    @Test func gitlabUrlWithNoIssueNumber() {
        let result = TicketExtractor.extractTicketId(from: "https://gitlab.com/org/repo/-/issues/")
        #expect(result == nil)
    }

    // MARK: - Shortcut

    @Test func shortcutStandardUrl() {
        let result = TicketExtractor.extractTicketId(from: "https://app.shortcut.com/myorg/story/12345/some-title")
        #expect(result == "sc-12345")
    }

    @Test func shortcutUrlWithTrailingSlash() {
        let result = TicketExtractor.extractTicketId(from: "https://app.shortcut.com/myorg/story/12345/")
        #expect(result == "sc-12345")
    }

    @Test func shortcutUrlWithQueryParams() {
        let result = TicketExtractor.extractTicketId(from: "https://app.shortcut.com/myorg/story/12345/some-title?q=1")
        #expect(result == "sc-12345")
    }

    @Test func shortcutUrlWithNoStoryNumber() {
        let result = TicketExtractor.extractTicketId(from: "https://app.shortcut.com/myorg/story/")
        #expect(result == nil)
    }

    // MARK: - Edge Cases

    @Test func emptyStringReturnsNil() {
        let result = TicketExtractor.extractTicketId(from: "")
        #expect(result == nil)
    }

    @Test func randomUrlReturnsNil() {
        let result = TicketExtractor.extractTicketId(from: "https://example.com/foo")
        #expect(result == nil)
    }

    @Test func malformedUrlReturnsNil() {
        let result = TicketExtractor.extractTicketId(from: "not a url at all")
        #expect(result == nil)
    }

    @Test func whitespaceOnlyReturnsNil() {
        let result = TicketExtractor.extractTicketId(from: "   ")
        #expect(result == nil)
    }

    @Test func urlWithLeadingAndTrailingWhitespace() {
        let result = TicketExtractor.extractTicketId(from: "  https://linear.app/team/issue/LIN-99  ")
        #expect(result == "LIN-99")
    }
}
