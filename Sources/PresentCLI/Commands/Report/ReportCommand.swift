import ArgumentParser

struct ReportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "View reports and summaries.",
        discussion: """
            View time tracking summaries for today, this week, or this month. \
            Use `report export` to export raw session data as CSV.
            """,
        subcommands: [
            ReportTodayCommand.self,
            ReportWeekCommand.self,
            ReportMonthCommand.self,
            ReportExportCommand.self,
        ],
    )
}
