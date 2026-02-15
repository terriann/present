import ArgumentParser
import PresentCore

@main
struct PresentCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "present",
        abstract: "Present — time tracking from the command line.",
        subcommands: [
            StatusCommand.self,
            StartCommand.self,
            StopCommand.self,
            PauseCommand.self,
            ResumeCommand.self,
            CancelCommand.self,
            NoteCommand.self,
            LogCommand.self,
            ActivitiesCommand.self,
        ],
        defaultSubcommand: StatusCommand.self
    )
}
