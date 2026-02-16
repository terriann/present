import ArgumentParser
import Foundation
import PresentCore

struct ReportExportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export sessions as CSV."
    )

    @Option(name: .long, help: "Start date (YYYY-MM-DD, inclusive). Defaults to start of current month.")
    var from: String?

    @Option(name: .long, help: "End date (YYYY-MM-DD, inclusive). Defaults to today.")
    var to: String?

    func run() async throws {
        let service = try CLIServiceFactory.makeService()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current

        let calendar = Calendar.current

        let fromDate: Date
        if let from {
            guard let parsed = formatter.date(from: from) else {
                print("Invalid date format: \(from). Use YYYY-MM-DD.")
                throw ExitCode.failure
            }
            fromDate = calendar.startOfDay(for: parsed)
        } else {
            // Default to start of current month
            fromDate = calendar.dateInterval(of: .month, for: Date())!.start
        }

        let toDate: Date
        if let to {
            guard let parsed = formatter.date(from: to) else {
                print("Invalid date format: \(to). Use YYYY-MM-DD.")
                throw ExitCode.failure
            }
            // Inclusive: end of the specified day
            toDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: parsed))!
        } else {
            toDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        }

        let data = try await service.exportCSV(from: fromDate, to: toDate, includeArchived: false)
        if let csv = String(data: data, encoding: .utf8) {
            print(csv, terminator: "")
        }
    }
}
