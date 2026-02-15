import ArgumentParser
import PresentCore

struct ActivitiesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "activities",
        abstract: "Manage activities.",
        subcommands: [ActivitiesListCommand.self, ActivitiesArchiveCommand.self],
        defaultSubcommand: ActivitiesListCommand.self
    )
}

struct ActivitiesListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List active activities."
    )

    @Flag(name: .long, help: "Include archived activities.")
    var includeArchived = false

    func run() async throws {
        let service = try CLIServiceFactory.makeService()
        let activities = try await service.listActivities(includeArchived: includeArchived)

        if activities.isEmpty {
            print("No activities found.")
            return
        }

        for activity in activities {
            let archived = activity.isArchived ? " [archived]" : ""
            print("  [\(activity.id!)] \(activity.title)\(archived)")
        }
    }
}

struct ActivitiesArchiveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "archive",
        abstract: "Archive an activity."
    )

    @Argument(help: "Activity ID to archive.")
    var id: Int64

    func run() async throws {
        let service = try CLIServiceFactory.makeService()
        let result = try await service.archiveActivity(id: id)

        switch result {
        case .archived:
            let activity = try await service.getActivity(id: id)
            print("Archived \"\(activity.title)\"")
        case .promptDelete(let totalSeconds):
            let activity = try await service.getActivity(id: id)
            let duration = TimeFormatting.formatDuration(seconds: totalSeconds)
            print("\"\(activity.title)\" has only \(duration) tracked. Consider deleting instead.")
            print("To delete, use: present activities delete \(id)")
        }

        IPCClient().send(.dataChanged)
    }
}
