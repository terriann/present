import ArgumentParser
import Foundation
import PresentCore

struct SessionStartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start a session for an activity."
    )

    @Argument(help: "Activity name (creates if it doesn't exist).")
    var activityName: String

    @Option(name: .long, help: "Session type: work, rhythm, timebound.")
    var type: String = "work"

    @Option(name: .long, help: "Timer duration in minutes (for rhythm/timebound).")
    var minutes: Int?

    @Option(name: .long, help: "Break duration in minutes (overrides rhythm option default).")
    var breakMinutes: Int?

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()

        guard let sessionType = SessionType(rawValue: type) else {
            print("Invalid session type: \(type). Use: work, rhythm, timebound.")
            throw ExitCode.failure
        }

        let service = try CLIServiceFactory.makeService()

        // Resolve rhythm option and break duration
        var resolvedBreakMinutes: Int?
        if sessionType == .rhythm {
            let optionsStr = try await service.getPreference(key: PreferenceKey.rhythmDurationOptions) ?? ""
            let options: [RhythmOption] = optionsStr.isEmpty
                ? Constants.defaultRhythmDurationOptions
                : PreferenceKey.parseRhythmOptions(optionsStr)
            let validOptions = options.isEmpty ? Constants.defaultRhythmDurationOptions : options

            if let mins = minutes {
                guard let matched = validOptions.first(where: { $0.focusMinutes == mins }) else {
                    let formatted = validOptions.map { "\($0.focusMinutes) min (\($0.breakMinutes)m break)" }.joined(separator: ", ")
                    print("Invalid duration: \(mins) minutes. Available options: \(formatted)")
                    throw ExitCode.failure
                }
                resolvedBreakMinutes = breakMinutes ?? matched.breakMinutes
            } else {
                resolvedBreakMinutes = breakMinutes ?? validOptions.first?.breakMinutes
            }
        }

        // Find or create activity
        let activities = try await service.listActivities(includeArchived: false)
        let activity: Activity
        if let existing = activities.first(where: { $0.title.lowercased() == activityName.lowercased() }) {
            activity = existing
        } else {
            activity = try await service.createActivity(CreateActivityInput(title: activityName))
            if outputOptions.format == .text && outputOptions.field == nil {
                print("Created activity: \(activity.title)")
            }
        }

        let session = try await service.startSession(
            activityId: activity.id!,
            type: sessionType,
            timerMinutes: minutes,
            breakMinutes: resolvedBreakMinutes
        )

        switch outputOptions.format {
        case .json:
            try outputOptions.printJSON(session.toJSONDict(activity: activity))

        case .text:
            let textFields = session.toTextFields(activity: activity)
            if try outputOptions.printTextField(textFields) { break }

            let config = SessionTypeConfig.config(for: session.sessionType)
            print("Started \(config.displayName) for \"\(activity.title)\"")

            if let timer = session.timerLengthMinutes {
                print("Timer: \(timer) minutes")
                if let brk = session.breakMinutes {
                    print("Break: \(brk) minutes")
                }
            }

        case .csv:
            print("CSV output not supported for session start.")
            throw ExitCode.failure
        }

        IPCClient().send(.sessionStarted)
    }
}
