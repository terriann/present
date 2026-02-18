import ArgumentParser
import Foundation
import PresentCore

struct TagDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a tag.",
        discussion: """
            Permanently deletes a tag and removes it from all activities. \
            This action cannot be undone.

            ## Examples

            # Delete a tag
            $ present-cli tag delete 3

            # Delete and confirm via text
            $ present-cli tag delete 3 -f text
            """
    )

    @Argument(help: "Tag ID to delete.")
    var id: Int64

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        let tags = try await service.listTags()
        let tag = tags.first(where: { $0.id == id })

        try await service.deleteTag(id: id)

        switch outputOptions.format {
        case .json:
            var dict: [String: Any] = ["id": id, "deleted": true]
            if let tag { dict["name"] = tag.name }
            try outputOptions.printJSON(dict)

        case .text:
            var textFields: [String: String] = ["id": "\(id)", "deleted": "true"]
            if let tag { textFields["name"] = tag.name }
            if try outputOptions.printTextField(textFields) { break }

            if let tag {
                print("Deleted tag: \(tag.name)")
            } else {
                print("Deleted tag \(id)")
            }

        case .csv:
            print("CSV output not supported for tag delete.")
            throw ExitCode.failure
        }

        IPCClient().send(.dataChanged)
    }
}
