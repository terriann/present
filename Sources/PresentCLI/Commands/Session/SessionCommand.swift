import ArgumentParser

struct SessionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "session",
        abstract: "Manage sessions.",
        discussion: """
            Sessions track time spent on activities. Each session has a type \
            (work, rhythm, or timebound), a state (running, paused, or \
            completed), and belongs to a single activity.

            Use `session start` to begin a new session, `session current` to \
            interact with the active session, and `session list` to browse \
            past sessions.
            """,
        subcommands: [
            SessionStartCommand.self,
            SessionAddCommand.self,
            SessionGetCommand.self,
            SessionListCommand.self,
            SessionUpdateCommand.self,
            SessionDeleteCommand.self,
            SessionCurrentCommand.self,
        ],
    )
}
