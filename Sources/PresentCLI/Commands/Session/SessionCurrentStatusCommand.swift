import ArgumentParser
import Foundation
import PresentCore

struct SessionCurrentStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show current session status.",
        discussion: """
            If a session is running, shows its details including elapsed time \
            and remaining time (for timed sessions). If no session is active, \
            reports that no session is running.

            ## Examples

            # Check if a session is running
            $ present-cli session current status

            # Shorthand (status is the default subcommand)
            $ present-cli session current

            # Get elapsed seconds for scripting
            $ present-cli session current status --field elapsedSeconds

            # Check status in text format
            $ present-cli session current status -f text
            """
    )

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()

        if let (session, activity) = try await service.currentSession() {
            let elapsed = Int(Date().timeIntervalSince(session.startedAt)) - session.totalPausedSeconds

            switch outputOptions.format {
            case .json:
                var dict = session.toJSONDict(activity: activity)
                dict["active"] = true
                dict["elapsedSeconds"] = elapsed
                if let timer = session.timerLengthMinutes {
                    dict["remainingSeconds"] = max(0, timer * 60 - elapsed)
                }
                try outputOptions.printJSON(dict)

            case .text:
                var textFields = session.toTextFields(activity: activity)
                textFields["active"] = "true"
                textFields["elapsed"] = TimeFormatting.formatTimer(seconds: elapsed)
                textFields["elapsedSeconds"] = "\(elapsed)"
                if let timer = session.timerLengthMinutes {
                    let remaining = max(0, timer * 60 - elapsed)
                    textFields["remaining"] = TimeFormatting.formatTimer(seconds: remaining)
                    textFields["remainingSeconds"] = "\(remaining)"
                }
                if try outputOptions.printTextField(textFields) { return }

                let stateLabel = session.state == .paused ? " (paused)" : ""
                print("Active: \(activity.title)\(stateLabel)")
                print("Type: \(SessionTypeConfig.config(for: session.sessionType).displayName)")
                print("Elapsed: \(TimeFormatting.formatTimer(seconds: elapsed))")

                if let timer = session.timerLengthMinutes {
                    let remaining = max(0, timer * 60 - elapsed)
                    print("Remaining: \(TimeFormatting.formatTimer(seconds: remaining))")
                }

            case .csv:
                print("CSV output not supported for session current status.")
                throw ExitCode.failure
            }
        } else {
            switch outputOptions.format {
            case .json:
                let dict: [String: Any] = [
                    "active": false,
                ]
                try outputOptions.printJSON(dict)

            case .text:
                let textFields: [String: String] = [
                    "active": "false",
                ]
                if try outputOptions.printTextField(textFields) { return }
                print("No active session.")

            case .csv:
                print("CSV output not supported for session current status.")
                throw ExitCode.failure
            }
        }
    }
}
