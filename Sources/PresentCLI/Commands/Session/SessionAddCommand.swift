import ArgumentParser
import Foundation
import PresentCore

struct SessionAddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a completed session with specific start and end times.",
        discussion: """
            Creates a backdated completed session. Useful for logging time \
            that was tracked elsewhere or forgotten. The session is inserted \
            as completed with the duration calculated from the timestamps.

            Timestamps use ISO8601 format (e.g., 2026-01-15T09:30:00). \
            Both start and end times must not be in the future; end time must be after start.

            ## Examples

            # Add a 1-hour work session
            $ present-cli session add 1 \\
                --started-at 2026-01-15T09:00:00 \\
                --ended-at 2026-01-15T10:00:00

            # Add a rhythm session with timer info
            $ present-cli session add 1 \\
                --started-at 2026-01-15T09:00:00 \\
                --ended-at 2026-01-15T09:25:00 \\
                --type rhythm --minutes 25 --break-minutes 5

            # Get just the session ID
            $ present-cli session add 1 \\
                --started-at 2026-01-15T09:00:00 \\
                --ended-at 2026-01-15T10:00:00 \\
                --field sessionId
            """
    )

    @Argument(help: "Activity ID.")
    var activityId: Int64

    @Option(name: .long, help: "Session start time (ISO8601, e.g., 2026-01-15T09:30:00).")
    var startedAt: String

    @Option(name: .long, help: "Session end time (ISO8601, e.g., 2026-01-15T10:30:00).")
    var endedAt: String

    @Option(name: .long, help: "Session type: work, rhythm, timebound.")
    var type: String = "work"

    @Option(name: .long, help: "Timer duration in minutes (for rhythm/timebound).")
    var minutes: Int?

    @Option(name: .long, help: "Break duration in minutes (for rhythm).")
    var breakMinutes: Int?

    @Option(name: .long, help: "Session note (free text).")
    var note: String?

    @Option(name: .long, help: "Link URL (ticket ID extracted automatically).")
    var link: String?

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()

        let sessionType = try SessionType.parseOrFail(type)

        let startDate = try DateParsing.parseDateTimeOrFail(startedAt, label: "start time")
        let endDate = try DateParsing.parseDateTimeOrFail(endedAt, label: "end time")

        let now = Date()
        if startDate > now {
            print("Start time cannot be in the future.")
            throw ExitCode.failure
        }
        if endDate > now {
            print("End time cannot be in the future.")
            throw ExitCode.failure
        }

        let service = try CLIServiceFactory.makeService()
        let input = CreateBackdatedSessionInput(
            activityId: activityId,
            sessionType: sessionType,
            startedAt: startDate,
            endedAt: endDate,
            timerLengthMinutes: minutes,
            breakMinutes: breakMinutes,
            note: note,
            link: link
        )

        let session = try await service.createBackdatedSession(input)
        let activity = try await service.getActivity(id: activityId)

        switch outputOptions.format {
        case .json:
            try outputOptions.printJSON(session.toJSONDict(activity: activity))

        case .text:
            let textFields = session.toTextFields(activity: activity)
            if try outputOptions.printTextField(textFields) { break }

            let duration = session.durationSeconds.map { TimeFormatting.formatDuration(seconds: $0) } ?? "—"
            let typeLabel = SessionTypeConfig.config(for: session.sessionType).displayName
            print("Added \(typeLabel) for \"\(activity.title)\" (\(duration))")

        case .csv:
            try outputOptions.throwCSVNotSupported(for: "session add")
        }

        IPCClient().send(.dataChanged)
    }

}
