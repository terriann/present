import ArgumentParser
import PresentCore

@main
struct PresentCLI: AsyncParsableCommand {
    static let version = Constants.cliVersion

    static let configuration = CommandConfiguration(
        commandName: "present-cli",
        abstract: "Present — time tracking from the command line.",
        version: version,
        subcommands: [
            SessionCommand.self,
            ActivityCommand.self,
            TagCommand.self,
            ReportCommand.self,
            ConfigCommand.self,
        ]
    )
}
