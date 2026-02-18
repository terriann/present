import ArgumentParser

struct ActivityTagCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tag",
        abstract: "Manage tags on an activity.",
        discussion: """
            Add, remove, set, or list tags associated with an activity. \
            Use `tag list` to find available tag IDs, or `tag add` to \
            create a new tag first.
            """,
        subcommands: [
            ActivityTagAddCommand.self,
            ActivityTagRemoveCommand.self,
            ActivityTagSetCommand.self,
            ActivityTagListCommand.self,
        ]
    )
}
