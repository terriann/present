import ArgumentParser

struct SessionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "session",
        abstract: "Manage sessions.",
        subcommands: [
            SessionStatusCommand.self,
            SessionGetCommand.self,
            SessionStartCommand.self,
            SessionStopCommand.self,
            SessionPauseCommand.self,
            SessionResumeCommand.self,
            SessionCancelCommand.self,
            SessionSearchCommand.self,
        ],
    )
}
