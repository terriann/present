import ArgumentParser
import Foundation
import PresentCore

struct ReportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "View activity summary for a date range.",
        discussion: """
            Shows total tracked time and session count per activity for a \
            date range. Defaults to today when no flags are given.

            Dates use YYYY-MM-DD format and are inclusive on both ends.

            ## Examples

            # Today's summary (default)
            $ present-cli report

            # This week
            $ present-cli report --after 2026-02-10 --before 2026-02-16

            # Get total seconds for scripting
            $ present-cli report --field totalSeconds

            # Export as CSV
            $ present-cli report --after 2026-01-01 --before 2026-01-31 -f csv

            # Show as text
            $ present-cli report -f text
            """
    )

    @Option(name: .long, help: "Start date (YYYY-MM-DD, inclusive). Defaults to today.")
    var after: String?

    @Option(name: .long, help: "End date (YYYY-MM-DD, inclusive). Defaults to today.")
    var before: String?

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()

        let calendar = Calendar.current

        let fromDate: Date
        if let after {
            fromDate = calendar.startOfDay(for: try DateParsing.parseDateOrFail(after, label: "--after"))
        } else {
            fromDate = calendar.startOfDay(for: Date())
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
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) else {
                print("Failed to compute date range.")
                throw ExitCode.failure
            }
            toDate = nextDay
        }

        let service = try CLIServiceFactory.makeService()
        var activities = try await service.activitySummary(from: fromDate, to: toDate, includeArchived: true)

        // Include active/paused session if it falls within the date range
        var hasActiveSession = false
        let now = Date()
        if let (session, activity) = try await service.currentSession() {
            if session.startedAt < toDate && (session.endedAt ?? now) > fromDate {
                // Wall clock minus completed pauses. If currently paused, also subtract
                // time since the current pause began (totalPausedSeconds only reflects
                // completed pause intervals).
                var elapsed = Int(now.timeIntervalSince(session.startedAt)) - session.totalPausedSeconds
                if session.state == .paused, let pausedAt = session.lastPausedAt {
                    elapsed -= Int(now.timeIntervalSince(pausedAt))
                }
                elapsed = max(0, elapsed)
                hasActiveSession = true

                if let idx = activities.firstIndex(where: { $0.activity.id == activity.id }) {
                    activities[idx] = ActivitySummary(
                        activity: activities[idx].activity,
                        totalSeconds: activities[idx].totalSeconds + elapsed,
                        sessionCount: activities[idx].sessionCount + 1
                    )
                } else {
                    activities.append(ActivitySummary(
                        activity: activity,
                        totalSeconds: elapsed,
                        sessionCount: 1
                    ))
                }
            }
        }

        let totalSeconds = activities.reduce(0) { $0 + $1.totalSeconds }
        let sessionCount = activities.reduce(0) { $0 + $1.sessionCount }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate]

        let fromStr = isoFormatter.string(from: fromDate)
        // toDate is exclusive (day after before), so subtract a day for display
        let toDisplayDate = calendar.date(byAdding: .day, value: -1, to: toDate) ?? toDate
        let toStr = isoFormatter.string(from: toDisplayDate)

        switch outputOptions.format {
        case .json:
            var dict: [String: Any] = [
                "from": fromStr,
                "to": toStr,
                "totalSeconds": totalSeconds,
                "sessionCount": sessionCount,
                "activities": activities.map { $0.toJSONDict() },
            ]
            if hasActiveSession {
                dict["includesActiveSession"] = true
            }
            try outputOptions.printJSON(dict)

        case .text:
            let textFields: [String: String] = [
                "from": fromStr,
                "to": toStr,
                "totalSeconds": "\(totalSeconds)",
                "total": TimeFormatting.formatDuration(seconds: totalSeconds),
                "sessionCount": "\(sessionCount)",
            ]
            if try outputOptions.printTextField(textFields) { break }

            if activities.isEmpty {
                print("No sessions found.")
                return
            }

            let rangeLabel = fromStr == toStr ? fromStr : "\(fromStr) to \(toStr)"
            print("\(rangeLabel) \u{2014} \(sessionCount) sessions, \(TimeFormatting.formatDuration(seconds: totalSeconds))")
            print(String(repeating: "\u{2500}", count: 50))

            for actSummary in activities {
                let duration = TimeFormatting.formatDuration(seconds: actSummary.totalSeconds)
                print("  \(actSummary.activity.title): \(duration) (\(actSummary.sessionCount) sessions)")
            }

        case .csv:
            print("Activity,Total Seconds,Sessions")
            for actSummary in activities {
                let escapedTitle = escapeCSVField(actSummary.activity.title)
                print("\(escapedTitle),\(actSummary.totalSeconds),\(actSummary.sessionCount)")
            }
        }
    }
}
