import ArgumentParser

struct ActivityCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "activity",
        abstract: "Manage activities.",
        subcommands: [
            ActivityListCommand.self,
            ActivityAddCommand.self,
            ActivityGetCommand.self,
            ActivityUpdateCommand.self,
            ActivitySearchCommand.self,
            ActivityArchiveCommand.self,
            ActivityUnarchiveCommand.self,
            ActivityDeleteCommand.self,
            ActivityNoteCommand.self,
            ActivityTagCommand.self,
            ActivityUntagCommand.self,
        ],
    )
}
