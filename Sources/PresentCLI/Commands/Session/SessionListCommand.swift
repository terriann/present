import ArgumentParser
import Foundation
import PresentCore

struct SessionListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List sessions with filters.",
        discussion: """
            List and filter sessions by date range, type, or activity name. \
            Results are paginated (max 100 per page). All filters are optional \
            and can be combined.

            Dates use YYYY-MM-DD format and are inclusive on both ends.

            ## Examples

            # List all sessions from this week
            $ present-cli session list --after 2025-01-13 --before 2025-01-17

            # Find rhythm sessions for a specific activity
            $ present-cli session list --type rhythm --activity "Deep Work"

            # Export sessions as CSV
            $ present-cli session list --after 2025-01-01 -f csv

            # Get page 2 of results
            $ present-cli session list --page 2
            """
    )

    @Option(name: .long, help: "Show sessions after this date (YYYY-MM-DD, inclusive).")
    var after: String?

    @Option(name: .long, help: "Show sessions before this date (YYYY-MM-DD, inclusive).")
    var before: String?

    @Option(name: .long, help: "Filter by session type: work, rhythm, timebound.")
    var type: String?

    @Option(name: .long, help: "Filter by activity name (substring match).")
    var activity: String?

    @Option(name: [.short, .long], help: "Search session notes and ticket IDs.")
    var query: String?

    @Option(name: .long, help: "Page number (1-indexed, max 100 results per page).")
    var page: Int = 1

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()

        // Parse dates
        let calendar = Calendar.current

        let fromDate: Date
        if let after {
            fromDate = calendar.startOfDay(for: try DateParsing.parseDateOrFail(after, label: "--after"))
        } else {
            fromDate = Date.distantPast
        }

        let toDate: Date
        if let before {
            let parsed = try DateParsing.parseDateOrFail(before, label: "--before")
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: parsed)) else {
                print("Failed to compute date range.")
                throw ExitCode.failure
            }
            toDate = nextDay
        } else {
            toDate = Date.distantFuture
        }

        // Parse session type
        let sessionType = try type.map(SessionType.parseOrFail)

        // Resolve activity name to ID
        var activityId: Int64?
        if let activityName = activity {
            let activities = try await service.listActivities(includeArchived: true)
            let matches = activities.filter { $0.title.localizedCaseInsensitiveContains(activityName) }
            if matches.isEmpty {
                print("No activity found matching \"\(activityName)\".")
                throw ExitCode.failure
            }
            if matches.count == 1 {
                activityId = matches.first?.id
            } else {
                activityId = nil
            }
        }

        // Fetch sessions
        let allSessions = try await service.listSessions(
            from: fromDate,
            to: toDate,
            type: sessionType,
            activityId: activityId,
            includeArchived: true,
            query: query
        )

        // Post-filter by activity name if multiple matches
        var sessions = allSessions
        if let activityName = activity, activityId == nil {
            sessions = sessions.filter { $0.1.title.localizedCaseInsensitiveContains(activityName) }
        }

        // Paginate
        let pageSize = 100
        guard page >= 1 else {
            print("Page number must be at least 1.")
            throw ExitCode.failure
        }
        let validPage = page
        let startIndex = (validPage - 1) * pageSize
        let totalCount = sessions.count
        let totalPages = max(1, (totalCount + pageSize - 1) / pageSize)

        guard startIndex < totalCount || totalCount == 0 else {
            print("Page \(validPage) is out of range. Total pages: \(totalPages).")
            throw ExitCode.failure
        }

        let pageResults = totalCount > 0
            ? Array(sessions[startIndex..<min(startIndex + pageSize, totalCount)])
            : []

        switch outputOptions.format {
        case .json:
            let items: [[String: Any]] = pageResults.map { session, act in
                session.toJSONDict(activity: act)
            }
            let result: [String: Any] = [
                "sessions": items,
                "page": validPage,
                "totalPages": totalPages,
                "totalCount": totalCount,
            ]
            try outputOptions.printJSON(result)

        case .text:
            let textFields: [String: String] = [
                "page": "\(validPage)",
                "totalPages": "\(totalPages)",
                "totalCount": "\(totalCount)",
            ]
            if try outputOptions.printTextField(textFields) { break }

            if pageResults.isEmpty {
                print("No sessions found.")
                return
            }

            print("Sessions (page \(validPage)/\(totalPages), \(totalCount) total)")
            print(String(repeating: "\u{2500}", count: 60))

            for (session, act) in pageResults {
                let dateStr = TimeFormatting.formatDate(session.startedAt)
                let timeStr = TimeFormatting.formatTime(session.startedAt)
                let duration = session.durationSeconds.map { TimeFormatting.formatDuration(seconds: $0) } ?? "\u{2014}"
                let typeLabel = SessionTypeConfig.config(for: session.sessionType).displayName
                print("  [\(session.id ?? 0)] \(dateStr) \(timeStr) \u{2014} \(act.title) (\(typeLabel)) \(duration)")
            }

            if totalPages > 1 {
                print("\nPage \(validPage) of \(totalPages). Use --page to navigate.")
            }

        case .csv:
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]
            print("Session ID,Activity,Type,State,Started At,Ended At,Duration (seconds)")
            for (session, act) in pageResults {
                let escapedTitle = escapeCSVField(act.title)
                let endedStr = session.endedAt.map { isoFormatter.string(from: $0) } ?? ""
                let durationStr = session.durationSeconds.map { String($0) } ?? ""
                print("\(session.id ?? 0),\(escapedTitle),\(session.sessionType.rawValue),\(session.state.rawValue),\(isoFormatter.string(from: session.startedAt)),\(endedStr),\(durationStr)")
            }
        }
    }
}
