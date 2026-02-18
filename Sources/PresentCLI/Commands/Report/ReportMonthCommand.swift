import ArgumentParser
import Foundation
import PresentCore

struct ReportMonthCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "month",
        abstract: "Show this month's summary.",
        discussion: """
            Shows total tracked time for the current month with a weekly \
            breakdown and per-activity totals.

            ## Examples

            # Show this month's summary
            $ present-cli report month

            # Show as text with weekly breakdown
            $ present-cli report month -f text

            # Get total seconds for scripting
            $ present-cli report month --field totalSeconds

            # Export weekly breakdown as CSV
            $ present-cli report month -f csv
            """
    )

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        let summary = try await service.monthlySummary(monthOf: Date(), includeArchived: true, weekStartDay: Calendar.current.firstWeekday)

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM yyyy"

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
                print("No sessions logged this month.")
                return
            }

            print("\(monthFormatter.string(from: summary.monthOf)) \u{2014} \(summary.sessionCount) sessions, \(TimeFormatting.formatDuration(seconds: summary.totalSeconds))")
            print(String(repeating: "\u{2500}", count: 50))

            for weekly in summary.weeklyBreakdown where weekly.sessionCount > 0 {
                let weekStr = TimeFormatting.formatDate(weekly.weekOf)
                print("  Week of \(weekStr): \(TimeFormatting.formatDuration(seconds: weekly.totalSeconds)) (\(weekly.sessionCount) sessions)")
            }

            print()
            print("By Activity:")
            for actSummary in summary.activities {
                let duration = TimeFormatting.formatDuration(seconds: actSummary.totalSeconds)
                print("  \(actSummary.activity.title): \(duration)")
            }

        case .csv:
            print("Week Of,Total Seconds,Sessions")
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            for weekly in summary.weeklyBreakdown where weekly.sessionCount > 0 {
                print("\(dateFormatter.string(from: weekly.weekOf)),\(weekly.totalSeconds),\(weekly.sessionCount)")
            }
        }
    }
}
