import ArgumentParser

struct SessionCurrentCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "current",
        abstract: "Manage the current session.",
        discussion: """
            Commands for interacting with the currently active session: \
            check status, stop, pause, resume, or cancel.
            """,
        subcommands: [
            SessionCurrentStatusCommand.self,
            SessionStopCommand.self,
            SessionPauseCommand.self,
            SessionResumeCommand.self,
            SessionCancelCommand.self,
        ],
        defaultSubcommand: SessionCurrentStatusCommand.self
    )
}
