import ArgumentParser

struct TagCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tag",
        abstract: "Manage tags.",
        subcommands: [
            TagListCommand.self,
            TagAddCommand.self,
            TagGetCommand.self,
            TagUpdateCommand.self,
            TagDeleteCommand.self,
        ],
    )
}
