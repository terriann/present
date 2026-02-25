import ArgumentParser

struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "View and update preferences.",
        discussion: """
            Manage application preferences. Changes are synced to the app \
            via IPC when it is running.
            """,
        subcommands: [
            ConfigListCommand.self,
            ConfigGetCommand.self,
            ConfigSetCommand.self,
        ]
    )
}
