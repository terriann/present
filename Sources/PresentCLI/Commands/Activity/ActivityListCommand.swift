import ArgumentParser
import Foundation
import PresentCore

struct ActivityListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List activities.",
        discussion: """
            Lists all activities, including archived ones. Results are \
            paginated (max 100 per page).

            ## Examples

            # List activities as JSON (default, page 1)
            $ present-cli activity list

            # List in text format
            $ present-cli activity list -f text

            # Export as CSV
            $ present-cli activity list -f csv

            # Get page 2
            $ present-cli activity list --page 2
            """
    )

    @Option(name: .long, help: "Page number (1-indexed, max 100 results per page).")
    var page: Int = 1

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()
        let service = try CLIServiceFactory.makeService()

        // SQL-level pagination
        let pageSize = 100
        guard page >= 1 else {
            CLIError.print("Page number must be at least 1.")
            throw ExitCode.failure
        }
        let offset = (page - 1) * pageSize
        let totalCount = try await service.countActivities(includeArchived: true, includeSystem: false)
        let totalPages = max(1, (totalCount + pageSize - 1) / pageSize)

        guard offset < totalCount || totalCount == 0 else {
            CLIError.print("Page \(page) is out of range. Total pages: \(totalPages).")
            throw ExitCode.failure
        }

        let activities = try await service.listActivities(
            includeArchived: true, includeSystem: false,
            limit: pageSize, offset: offset
        )

        let activityIds = activities.compactMap(\.id)
        let tagsByActivity = try await service.tagsForActivities(activityIds: activityIds)

        switch outputOptions.format {
        case .json:
            let items = activities.map {
                $0.toJSONDict(tags: tagsByActivity[$0.id ?? 0] ?? [])
            }
            let result: [String: Any] = [
                "activities": items,
                "page": page,
                "totalPages": totalPages,
                "totalCount": totalCount,
            ]
            try outputOptions.printJSON(result)

        case .text:
            let textFields: [String: String] = [
                "page": "\(page)",
                "totalPages": "\(totalPages)",
                "totalCount": "\(totalCount)",
            ]
            if try outputOptions.printTextField(textFields) { break }

            if activities.isEmpty {
                print("No activities found.")
                return
            }

            print("Activities (page \(page)/\(totalPages), \(totalCount) total)")
            for activity in activities {
                let archived = activity.isArchived ? " [archived]" : ""
                print("  [\(activity.id ?? 0)] \(activity.title)\(archived)")
            }

            if totalPages > 1 {
                print("\nPage \(page) of \(totalPages). Use --page to navigate.")
            }

        case .csv:
            print("ID,Title,Archived,External ID,Link")
            for activity in activities {
                let escapedTitle = escapeCSVField(activity.title)
                let externalId = escapeCSVField(activity.externalId ?? "")
                let link = escapeCSVField(activity.link ?? "")
                print("\(activity.id ?? 0),\(escapedTitle),\(activity.isArchived),\(externalId),\(link)")
            }
        }
    }
}
