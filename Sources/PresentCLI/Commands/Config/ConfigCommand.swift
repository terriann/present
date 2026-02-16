import ArgumentParser

struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "View and update preferences.",
        subcommands: [
            ConfigListCommand.self,
            ConfigGetCommand.self,
            ConfigSetCommand.self,
        ],
    )
}
