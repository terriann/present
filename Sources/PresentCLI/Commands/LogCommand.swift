import ArgumentParser
import Foundation
import PresentCore

struct LogCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "log",
        abstract: "Show logged sessions.",
        subcommands: [LogTodayCommand.self, LogWeekCommand.self],
        defaultSubcommand: LogTodayCommand.self
    )
}

struct LogTodayCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "today",
        abstract: "Show today's logged sessions."
    )

    func run() async throws {
        let service = try CLIServiceFactory.makeService()
        let summary = try await service.dailySummary(date: Date(), includeArchived: false)

        if summary.sessionCount == 0 {
            print("No sessions logged today.")
            return
        }

        print("Today — \(summary.sessionCount) sessions, \(TimeFormatting.formatDuration(seconds: summary.totalSeconds))")
        print(String(repeating: "─", count: 50))

        for actSummary in summary.activities {
            let duration = TimeFormatting.formatDuration(seconds: actSummary.totalSeconds)
            print("  \(actSummary.activity.title): \(duration) (\(actSummary.sessionCount) sessions)")
        }
    }
}

struct LogWeekCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "week",
        abstract: "Show this week's summary."
    )

    func run() async throws {
        let service = try CLIServiceFactory.makeService()
        let summary = try await service.weeklySummary(weekOf: Date(), includeArchived: false)

        if summary.sessionCount == 0 {
            print("No sessions logged this week.")
            return
        }

        print("This Week — \(summary.sessionCount) sessions, \(TimeFormatting.formatDuration(seconds: summary.totalSeconds))")
        print(String(repeating: "─", count: 50))

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
    }
}
