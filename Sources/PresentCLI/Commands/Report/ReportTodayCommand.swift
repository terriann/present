import ArgumentParser
import Foundation
import PresentCore

struct ReportTodayCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "today",
        abstract: "Show today's summary.",
        discussion: """
            Shows total tracked time and session count for today, broken \
            down by activity.

            ## Examples

            # Show today's summary
            $ present-cli report today

            # Show as text
            $ present-cli report today -f text

            # Get just the total seconds for scripting
            $ present-cli report today --field totalSeconds

            # Export today's breakdown as CSV
            $ present-cli report today -f csv
            """
    )

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        let summary = try await service.dailySummary(date: Date(), includeArchived: true)

        switch outputOptions.format {
        case .json:
            try outputOptions.printJSON(summary.toJSONDict())

        case .text:
            let textFields: [String: String] = [
                "totalSeconds": "\(summary.totalSeconds)",
                "total": TimeFormatting.formatDuration(seconds: summary.totalSeconds),
                "sessionCount": "\(summary.sessionCount)",
            ]
            if try outputOptions.printTextField(textFields) { break }

            if summary.sessionCount == 0 {
                print("No sessions logged today.")
                return
            }

            print("Today \u{2014} \(summary.sessionCount) sessions, \(TimeFormatting.formatDuration(seconds: summary.totalSeconds))")
            print(String(repeating: "\u{2500}", count: 50))

            for actSummary in summary.activities {
                let duration = TimeFormatting.formatDuration(seconds: actSummary.totalSeconds)
                print("  \(actSummary.activity.title): \(duration) (\(actSummary.sessionCount) sessions)")
            }

        case .csv:
            print("Activity,Total Seconds,Sessions")
            for actSummary in summary.activities {
                let escapedTitle = actSummary.activity.title.contains(",") ? "\"\(actSummary.activity.title)\"" : actSummary.activity.title
                print("\(escapedTitle),\(actSummary.totalSeconds),\(actSummary.sessionCount)")
            }
        }
    }
}
