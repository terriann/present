import ArgumentParser
import Foundation
import PresentCore

struct ActivityGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Show activity details."
    )

    @Argument(help: "Activity ID.")
    var id: Int64

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        let activity = try await service.getActivity(id: id)
        let tags = try await service.tagsForActivity(activityId: id)

        switch outputOptions.format {
        case .json:
            try outputOptions.printJSON(activity.toJSONDict(tags: tags))

        case .text:
            if try outputOptions.printTextField(activity.toTextFields(tags: tags)) { break }

            let archived = activity.isArchived ? " [archived]" : ""
            print("[\(activity.id!)] \(activity.title)\(archived)")
            if let externalId = activity.externalId {
                print("External ID: \(externalId)")
            }
            if let link = activity.link {
                print("Link: \(link)")
            }
            if !tags.isEmpty {
                let tagNames = tags.map { $0.name }.joined(separator: ", ")
                print("Tags: \(tagNames)")
            }
            if let notes = activity.notes, !notes.isEmpty {
                print("Notes:")
                print(notes)
            }

        case .csv:
            print("CSV output not supported for activity get.")
            throw ExitCode.failure
        }
    }
}
