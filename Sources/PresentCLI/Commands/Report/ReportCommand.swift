import ArgumentParser

struct ReportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "View reports and summaries.",
        subcommands: [
            ReportTodayCommand.self,
            ReportWeekCommand.self,
            ReportMonthCommand.self,
            ReportExportCommand.self,
        ],
    )
}
