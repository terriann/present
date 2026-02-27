import ArgumentParser
import Foundation
import PresentCore

struct SessionUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update a session's note or link.",
        discussion: """
            Updates the note and/or link on an existing session. Works on both \
            active and completed sessions.

            When a recognized project management URL is provided as a link, \
            Present extracts a ticket ID automatically (Linear, Jira, GitHub, \
            GitLab, Shortcut).

            Use --clear-note or --clear-link to remove a previously set value.

            ## Examples

            # Add a note to a session
            $ present-cli session update 42 --note "Reviewed PR feedback"

            # Add a ticket link
            $ present-cli session update 42 --link "https://linear.app/team/issue/LIN-123"

            # Clear the note
            $ present-cli session update 42 --clear-note

            # Update both at once
            $ present-cli session update 42 --note "Sprint planning" --link "https://org.atlassian.net/browse/PROJ-99"
            """
    )

    @Argument(help: "Session ID.")
    var id: Int64

    @Option(name: .long, help: "Session note (free text).")
    var note: String?

    @Option(name: .long, help: "Link URL (ticket ID extracted automatically).")
    var link: String?

    @Flag(name: .long, help: "Clear the session note.")
    var clearNote = false

    @Flag(name: .long, help: "Clear the session link and ticket ID.")
    var clearLink = false

    @OptionGroup var outputOptions: OutputOptions

    func run() async throws {
        try outputOptions.validateOptions()

        guard note != nil || link != nil || clearNote || clearLink else {
            print("Provide at least one field to update (--note, --link, --clear-note, --clear-link).")
            throw ExitCode.failure
        }

        let resolvedNote: String? = if clearNote {
            ""
        } else {
            note
        }

        let resolvedLink: String? = if clearLink {
            ""
        } else {
            link
        }

        let service = try CLIServiceFactory.makeService()
        let input = UpdateSessionInput(note: resolvedNote, link: resolvedLink)
        let session = try await service.updateSession(id: id, input)
        let (_, activity) = try await service.getSession(id: id)

        switch outputOptions.format {
        case .json:
            try outputOptions.printJSON(session.toJSONDict(activity: activity))

        case .text:
            let textFields = session.toTextFields(activity: activity)
            if try outputOptions.printTextField(textFields) { break }
            print("Updated session \(session.id!) for \"\(activity.title)\"")

        case .csv:
            print("CSV output not supported for session update.")
            throw ExitCode.failure
        }

        IPCClient().send(.sessionUpdated)
    }
}
