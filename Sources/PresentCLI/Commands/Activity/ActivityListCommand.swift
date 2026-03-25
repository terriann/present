import ArgumentParser
import Foundation
import PresentCore

struct ActivityListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List activities.",
        discussion: """
            Lists all activities, including archived ones. Use the output \
            format options to control how results are displayed.

            ## Examples

            # List all activities as JSON (default)
            $ present-cli activity list

            # List in text format
            $ present-cli activity list -f text

            # Export as CSV
            $ present-cli activity list -f csv
            """
    )

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()
        let activities = try await service.listActivities(includeArchived: true)
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
                print("No activities found.")
                return
            }

            for activity in activities {
                let archived = activity.isArchived ? " [archived]" : ""
                print("  [\(activity.id ?? 0)] \(activity.title)\(archived)")
            }

        case .csv:
            print("ID,Title,Archived,External ID,Link")
            for activity in activities {
                let escapedTitle = escapeCSVField(activity.title)
                let externalId = activity.externalId ?? ""
                let link = activity.link ?? ""
                print("\(activity.id ?? 0),\(escapedTitle),\(activity.isArchived),\(externalId),\(link)")
            }
        }
    }
}
