import ArgumentParser
import Foundation
import PresentCore

struct ActivitySearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search activities by name."
    )

    @Argument(help: "Search query.")
    var query: String

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        let activities = try await service.searchActivities(query: query)
        let activityIds = activities.compactMap(\.id)
        let tagsByActivity = try await service.tagsForActivities(activityIds: activityIds)

        switch outputOptions.format {
        case .json:
            try outputOptions.printJSONArray(activities.map {
                $0.toJSONDict(tags: tagsByActivity[$0.id!] ?? [])
            })

        case .text:
            if outputOptions.field != nil {
                print("--field is not supported for list output.")
                throw ExitCode.failure
            }

            if activities.isEmpty {
                print("No activities found matching \"\(query)\".")
                return
            }

            for activity in activities {
                let archived = activity.isArchived ? " [archived]" : ""
                print("  [\(activity.id!)] \(activity.title)\(archived)")
            }

        case .csv:
            print("ID,Title,Archived,External ID,Link")
            for activity in activities {
                let escapedTitle = activity.title.contains(",") ? "\"\(activity.title)\"" : activity.title
                let externalId = activity.externalId ?? ""
                let link = activity.link ?? ""
                print("\(activity.id!),\(escapedTitle),\(activity.isArchived),\(externalId),\(link)")
            }
        }
    }
}
