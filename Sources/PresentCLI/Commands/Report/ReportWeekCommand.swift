import ArgumentParser
import Foundation
import PresentCore

struct ReportWeekCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "week",
        abstract: "Show this week's summary.",
        discussion: """
            Shows total tracked time for the current week with a daily \
            breakdown and per-activity totals.

            ## Examples

            # Show this week's summary
            $ present-cli report week

            # Show as text with daily breakdown
            $ present-cli report week -f text

            # Get total seconds for scripting
            $ present-cli report week --field totalSeconds

            # Export daily breakdown as CSV
            $ present-cli report week -f csv
            """
    )

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        let summary = try await service.weeklySummary(weekOf: Date(), includeArchived: true, weekStartDay: Calendar.current.firstWeekday)

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
                print("No sessions logged this week.")
                return
            }

            print("This Week \u{2014} \(summary.sessionCount) sessions, \(TimeFormatting.formatDuration(seconds: summary.totalSeconds))")
            print(String(repeating: "\u{2500}", count: 50))

            for daily in summary.dailyBreakdown where daily.sessionCount > 0 {
                let dayStr = TimeFormatting.formatDate(daily.date)
                print("  \(dayStr): \(TimeFormatting.formatDuration(seconds: daily.totalSeconds)) (\(daily.sessionCount) sessions)")
            }

            print()
            print("By Activity:")
            for actSummary in summary.activities {
                let duration = TimeFormatting.formatDuration(seconds: actSummary.totalSeconds)
                print("  \(actSummary.activity.title): \(duration)")
            }

        case .csv:
            print("Day,Total Seconds,Sessions")
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            for daily in summary.dailyBreakdown where daily.sessionCount > 0 {
                print("\(dateFormatter.string(from: daily.date)),\(daily.totalSeconds),\(daily.sessionCount)")
            }
        }
    }
}
