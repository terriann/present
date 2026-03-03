import Foundation

/// Extracts a human-readable ticket ID from a project management URL.
///
/// Supported providers:
/// - **Linear**: `linear.app` URLs → `"LIN-123"`
/// - **Jira**: `atlassian.net/browse/` URLs → `"PROJ-123"`
/// - **GitHub**: `github.com/.../issues/` URLs → `"org/repo#123"`
/// - **GitLab**: `gitlab.com/.../-/issues/` URLs → `"org/repo#123"`
/// - **Shortcut**: `app.shortcut.com/.../story/` URLs → `"sc-12345"`
///
/// Returns `nil` for unrecognized URLs or invalid input.
public enum TicketExtractor {

    /// Scans free text for URLs using `NSDataDetector` and returns the first URL
    /// that yields a recognized ticket ID via ``extractTicketId(from:)``.
    ///
    /// - Parameter text: Free-form text that may contain URLs (plain or markdown).
    /// - Returns: A tuple of the matched URL string and its extracted ticket ID, or `nil`.
    public static func extractFirstTicketURL(from text: String) -> (url: String, ticketId: String)? {
        guard !text.isEmpty else { return nil }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)

        for match in matches {
            guard let url = match.url else { continue }
            let urlString = url.absoluteString
            if let ticketId = extractTicketId(from: urlString) {
                return (url: urlString, ticketId: ticketId)
            }
        }

        return nil
    }

    /// Attempts to extract a ticket ID from the given URL string.
    public static func extractTicketId(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased() else {
            return nil
        }

        let path = url.path

        if host.hasSuffix("linear.app") {
            return extractLinear(path: path)
        }
        if host.hasSuffix("atlassian.net") {
            return extractJira(path: path)
        }
        if host == "github.com" {
            return extractGitHub(path: path)
        }
        if host == "gitlab.com" {
            return extractGitLab(path: path)
        }
        if host == "app.shortcut.com" {
            return extractShortcut(path: path)
        }

        return nil
    }

    // MARK: - Provider Extractors

    /// Linear URLs: `https://linear.app/team/issue/LIN-123`
    /// The ticket ID is the last path component matching `[A-Z]+-\d+`.
    private static func extractLinear(path: String) -> String? {
        let components = path.split(separator: "/")
        for component in components.reversed() {
            let str = String(component)
            if str.range(of: #"^[A-Z]+-\d+$"#, options: .regularExpression) != nil {
                return str
            }
        }
        return nil
    }

    /// Jira URLs: `https://org.atlassian.net/browse/PROJ-123`
    /// The ticket ID follows `/browse/`.
    private static func extractJira(path: String) -> String? {
        let components = path.split(separator: "/")
        guard let browseIndex = components.firstIndex(of: "browse"),
              browseIndex + 1 < components.count else {
            return nil
        }
        let ticket = String(components[browseIndex + 1])
        if ticket.range(of: #"^[A-Z]+-\d+$"#, options: .regularExpression) != nil {
            return ticket
        }
        return nil
    }

    /// GitHub URLs: `https://github.com/org/repo/issues/123`
    /// Returns `"org/repo#123"`.
    private static func extractGitHub(path: String) -> String? {
        let components = path.split(separator: "/")
        // Expect: org, repo, "issues", number (at minimum indices 0-3)
        guard components.count >= 4 else { return nil }
        let issuesIndex = components.firstIndex(of: "issues")
        guard let idx = issuesIndex,
              idx >= 2,
              idx + 1 < components.count else {
            return nil
        }
        let org = components[idx - 2]
        let repo = components[idx - 1]
        let number = components[idx + 1]
        if number.allSatisfy(\.isNumber) && !number.isEmpty {
            return "\(org)/\(repo)#\(number)"
        }
        return nil
    }

    /// GitLab URLs: `https://gitlab.com/org/repo/-/issues/123`
    /// Returns `"org/repo#123"`.
    private static func extractGitLab(path: String) -> String? {
        let components = path.split(separator: "/")
        // Expect: org, repo, "-", "issues", number
        guard components.count >= 5 else { return nil }
        guard let dashIndex = components.firstIndex(of: "-"),
              dashIndex >= 2,
              dashIndex + 2 < components.count,
              components[dashIndex + 1] == "issues" else {
            return nil
        }
        let org = components[dashIndex - 2]
        let repo = components[dashIndex - 1]
        let number = components[dashIndex + 2]
        if number.allSatisfy(\.isNumber) && !number.isEmpty {
            return "\(org)/\(repo)#\(number)"
        }
        return nil
    }

    /// Shortcut URLs: `https://app.shortcut.com/org/story/12345/title`
    /// Returns `"sc-12345"`.
    private static func extractShortcut(path: String) -> String? {
        let components = path.split(separator: "/")
        guard let storyIndex = components.firstIndex(of: "story"),
              storyIndex + 1 < components.count else {
            return nil
        }
        let number = String(components[storyIndex + 1])
        if number.allSatisfy(\.isNumber) && !number.isEmpty {
            return "sc-\(number)"
        }
        return nil
    }
}
