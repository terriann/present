import ArgumentParser
import Foundation
import PresentCore

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show current session status."
    )

    func run() async throws {
        let service = try CLIServiceFactory.makeService()
        if let (session, activity) = try await service.currentSession() {
            let elapsed = Int(Date().timeIntervalSince(session.startedAt)) - session.totalPausedSeconds
            let stateLabel = session.state == .paused ? " (paused)" : ""
            print("Active: \(activity.title)\(stateLabel)")
            print("Type: \(SessionTypeConfig.config(for: session.sessionType).displayName)")
            print("Elapsed: \(TimeFormatting.formatTimer(seconds: elapsed))")

            if let timer = session.timerLengthMinutes {
                let remaining = max(0, timer * 60 - elapsed)
                print("Remaining: \(TimeFormatting.formatTimer(seconds: remaining))")
            }
        } else {
            print("No active session.")
            let summary = try await service.todaySummary()
            if summary.sessionCount > 0 {
                print("Today: \(summary.sessionCount) sessions, \(TimeFormatting.formatDuration(seconds: summary.totalSeconds))")
            }
        }
    }
}
