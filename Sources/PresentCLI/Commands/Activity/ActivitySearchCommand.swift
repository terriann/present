import ArgumentParser
import Foundation
import PresentCore

struct ActivitySearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search activities by name.",
        discussion: """
            Searches activities using full-text search on the activity name. \
            Returns matching activities with their tags.

            ## Examples

            # Search for activities matching "project"
            $ present-cli activity search "project"

            # Search and display as text
            $ present-cli activity search "work" -f text

            # Search and export as CSV
            $ present-cli activity search "client" -f csv
            """
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
                $0.toJSONDict(tags: tagsByActivity[$0.id ?? 0] ?? [])
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
                print("  [\(activity.id ?? 0)] \(activity.title)\(archived)")
            }

        case .csv:
            print("ID,Title,Archived,External ID,Link")
            for activity in activities {
                let escapedTitle = activity.title.contains(",") ? "\"\(activity.title)\"" : activity.title
                let externalId = activity.externalId ?? ""
                let link = activity.link ?? ""
                print("\(activity.id ?? 0),\(escapedTitle),\(activity.isArchived),\(externalId),\(link)")
            }
        }
    }
}
