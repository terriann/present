import ArgumentParser
import PresentCore

@main
struct PresentCLI: AsyncParsableCommand {
    static let version = "1.0.0 (0)"

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
        ],
    )
}
