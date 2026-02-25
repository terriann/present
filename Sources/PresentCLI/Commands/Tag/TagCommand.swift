import ArgumentParser

struct TagCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tag",
        abstract: "Manage tags.",
        discussion: """
            Tags are labels you can attach to activities for grouping and \
            filtering. Use `activity tag add` and `activity tag remove` to associate \
            tags with activities.
            """,
        subcommands: [
            TagListCommand.self,
            TagAddCommand.self,
            TagGetCommand.self,
            TagUpdateCommand.self,
            TagDeleteCommand.self,
        ]
    )
}
