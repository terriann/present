import ArgumentParser

struct ActivityCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "activity",
        abstract: "Manage activities.",
        discussion: """
            Activities are the things you track time against. Each activity \
            can have tags, notes, a link, and an external ID. Activities can \
            be archived when no longer in use.
            """,
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
        ]
    )
}
