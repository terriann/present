import ArgumentParser

struct SessionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "session",
        abstract: "Manage sessions.",
        discussion: """
            Sessions track time spent on activities. Each session has a type \
            (work, rhythm, or timebound), a state (running, paused, or \
            completed), and belongs to a single activity.
            """,
        subcommands: [
            SessionStatusCommand.self,
            SessionGetCommand.self,
            SessionStartCommand.self,
            SessionAddCommand.self,
            SessionListCommand.self,
            SessionStopCommand.self,
            SessionPauseCommand.self,
            SessionResumeCommand.self,
            SessionCancelCommand.self,
        ],
    )
}
