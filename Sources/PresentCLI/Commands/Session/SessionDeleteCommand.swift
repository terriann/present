import ArgumentParser
import Foundation
import PresentCore

struct SessionDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete one or more completed sessions by ID.",
        discussion: """
            Permanently removes completed or cancelled sessions. \
            Active (running or paused) sessions cannot be deleted — \
            stop them first with `session current stop` or cancel with \
            `session current cancel`.

            IDs that are not found are reported in the output but do not \
            cause a failure exit code.

            ## Examples

            # Delete a single session
            $ present-cli session delete 123

            # Delete multiple sessions at once
            $ present-cli session delete 123 456 789

            # Delete and get plain text output
            $ present-cli session delete 123 -f text
            """
    )

    @Argument(help: "Session ID(s) to delete.")
    var ids: [Int64]

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()

        if outputOptions.format == .csv {
            print("CSV output not supported for session delete.")
            throw ExitCode.failure
        }

        guard !ids.isEmpty else {
            print("At least one session ID is required.")
            throw ExitCode.failure
        }

        let service = try CLIServiceFactory.makeService()

        var deleted: [Int64] = []
        var notFound: [Int64] = []

        for id in ids {
            do {
                try await service.deleteSession(id: id)
                deleted.append(id)
            } catch PresentError.sessionNotFound {
                notFound.append(id)
            } catch PresentError.cannotDeleteActiveSession {
                print("Session \(id) is active. Stop it before deleting.")
                throw ExitCode.failure
            }
        }

        if !deleted.isEmpty {
            IPCClient().send(.dataChanged)
        }

        switch outputOptions.format {
        case .json:
            let dict: [String: Any] = [
                "deleted": deleted,
                "notFound": notFound,
                "deletedCount": deleted.count,
                "notFoundCount": notFound.count,
            ]
            try outputOptions.printJSON(dict)

        case .text:
            let textFields: [String: String] = [
                "deleted": deleted.map(String.init).joined(separator: ", "),
                "notFound": notFound.map(String.init).joined(separator: ", "),
                "deletedCount": String(deleted.count),
                "notFoundCount": String(notFound.count),
            ]
            if try outputOptions.printTextField(textFields) { break }

            if deleted.isEmpty {
                print("No sessions deleted.")
            } else {
                let idList = deleted.map(String.init).joined(separator: ", ")
                print("Deleted \(deleted.count) \(deleted.count == 1 ? "session" : "sessions") (\(idList))")
            }
            if !notFound.isEmpty {
                let idList = notFound.map(String.init).joined(separator: ", ")
                print("Not found: \(idList)")
            }

        case .csv:
            print("CSV output not supported for session delete.")
            throw ExitCode.failure
        }
    }
}
