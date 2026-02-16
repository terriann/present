import Testing
import Foundation
import ArgumentParser
@testable import PresentCLI

@Suite("CLI Command Tests")
struct CLICommandTests {

    // MARK: - PresentCLI Configuration

    @Test func rootCommandName() {
        #expect(PresentCLI.configuration.commandName == "present-cli")
    }

    @Test func rootCommandAbstract() {
        #expect(PresentCLI.configuration.abstract == "Present — time tracking from the command line.")
    }

    @Test func rootCommandHasExpectedSubcommands() {
        let subcommands = PresentCLI.configuration.subcommands
        #expect(subcommands.count == 9)

        let names = subcommands.map { $0.configuration.commandName ?? "" }
        #expect(names.contains("status"))
        #expect(names.contains("start"))
        #expect(names.contains("stop"))
        #expect(names.contains("pause"))
        #expect(names.contains("resume"))
        #expect(names.contains("cancel"))
        #expect(names.contains("note"))
        #expect(names.contains("log"))
        #expect(names.contains("activities"))
    }

    // MARK: - Default Subcommand

    @Test func defaultSubcommandIsStatus() throws {
        let command = try PresentCLI.parseAsRoot([])
        #expect(command is StatusCommand)
    }

    // MARK: - StatusCommand Parsing

    @Test func statusCommandParses() throws {
        let command = try PresentCLI.parseAsRoot(["status"])
        #expect(command is StatusCommand)
    }

    // MARK: - StartCommand Parsing

    @Test func startCommandParsesActivityName() throws {
        let command = try PresentCLI.parseAsRoot(["start", "My Task"])
        let start = try #require(command as? StartCommand)
        #expect(start.activityName == "My Task")
        #expect(start.type == "work")
        #expect(start.minutes == nil)
        #expect(start.breakMinutes == nil)
    }

    @Test func startCommandParsesTypeOption() throws {
        let command = try PresentCLI.parseAsRoot(["start", "Focus Work", "--type", "rhythm"])
        let start = try #require(command as? StartCommand)
        #expect(start.activityName == "Focus Work")
        #expect(start.type == "rhythm")
    }

    @Test func startCommandParsesMinutesOption() throws {
        let command = try PresentCLI.parseAsRoot(["start", "Task", "--minutes", "25"])
        let start = try #require(command as? StartCommand)
        #expect(start.minutes == 25)
    }

    @Test func startCommandParsesBreakMinutesOption() throws {
        let command = try PresentCLI.parseAsRoot(["start", "Task", "--break-minutes", "5"])
        let start = try #require(command as? StartCommand)
        #expect(start.breakMinutes == 5)
    }

    @Test func startCommandParsesAllOptions() throws {
        let command = try PresentCLI.parseAsRoot([
            "start", "Deep Work",
            "--type", "rhythm",
            "--minutes", "50",
            "--break-minutes", "10"
        ])
        let start = try #require(command as? StartCommand)
        #expect(start.activityName == "Deep Work")
        #expect(start.type == "rhythm")
        #expect(start.minutes == 50)
        #expect(start.breakMinutes == 10)
    }

    @Test func startCommandParsesTimeboundType() throws {
        let command = try PresentCLI.parseAsRoot(["start", "Meeting", "--type", "timebound", "--minutes", "60"])
        let start = try #require(command as? StartCommand)
        #expect(start.type == "timebound")
        #expect(start.minutes == 60)
    }

    @Test func startCommandRequiresActivityName() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["start"])
        }
    }

    @Test func startCommandAcceptsActivityNameWithSpaces() throws {
        let command = try PresentCLI.parseAsRoot(["start", "My Long Task Name"])
        let start = try #require(command as? StartCommand)
        #expect(start.activityName == "My Long Task Name")
    }

    @Test func startCommandDefaultTypeIsWork() throws {
        let command = try PresentCLI.parseAsRoot(["start", "Task"])
        let start = try #require(command as? StartCommand)
        #expect(start.type == "work")
    }

    // Note: invalid type values like "invalid" are accepted at parse time;
    // validation happens in run(). This is by design in the command.
    @Test func startCommandAcceptsAnyTypeString() throws {
        let command = try PresentCLI.parseAsRoot(["start", "Task", "--type", "invalid"])
        let start = try #require(command as? StartCommand)
        #expect(start.type == "invalid")
    }

    // MARK: - StopCommand Parsing

    @Test func stopCommandParses() throws {
        let command = try PresentCLI.parseAsRoot(["stop"])
        #expect(command is StopCommand)
    }

    @Test func stopCommandConfiguration() {
        #expect(StopCommand.configuration.commandName == "stop")
        #expect(StopCommand.configuration.abstract == "Stop the current session.")
    }

    // MARK: - PauseCommand Parsing

    @Test func pauseCommandParses() throws {
        let command = try PresentCLI.parseAsRoot(["pause"])
        #expect(command is PauseCommand)
    }

    @Test func pauseCommandConfiguration() {
        #expect(PauseCommand.configuration.commandName == "pause")
        #expect(PauseCommand.configuration.abstract == "Pause the current session.")
    }

    // MARK: - ResumeCommand Parsing

    @Test func resumeCommandParses() throws {
        let command = try PresentCLI.parseAsRoot(["resume"])
        #expect(command is ResumeCommand)
    }

    @Test func resumeCommandConfiguration() {
        #expect(ResumeCommand.configuration.commandName == "resume")
        #expect(ResumeCommand.configuration.abstract == "Resume a paused session.")
    }

    // MARK: - CancelCommand Parsing

    @Test func cancelCommandParses() throws {
        let command = try PresentCLI.parseAsRoot(["cancel"])
        #expect(command is CancelCommand)
    }

    @Test func cancelCommandConfiguration() {
        #expect(CancelCommand.configuration.commandName == "cancel")
        #expect(CancelCommand.configuration.abstract == "Cancel the current session without logging it.")
    }

    // MARK: - NoteCommand Parsing

    @Test func noteCommandParsesText() throws {
        let command = try PresentCLI.parseAsRoot(["note", "This is my note"])
        let note = try #require(command as? NoteCommand)
        #expect(note.text == "This is my note")
    }

    @Test func noteCommandRequiresText() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["note"])
        }
    }

    @Test func noteCommandConfiguration() {
        #expect(NoteCommand.configuration.commandName == "note")
        #expect(NoteCommand.configuration.abstract == "Append a note to the current activity.")
    }

    // MARK: - LogCommand Parsing

    @Test func logCommandConfiguration() {
        #expect(LogCommand.configuration.commandName == "log")
        #expect(LogCommand.configuration.abstract == "Show logged sessions.")

        let subcommands = LogCommand.configuration.subcommands
        #expect(subcommands.count == 2)
    }

    @Test func logDefaultSubcommandIsToday() throws {
        let command = try PresentCLI.parseAsRoot(["log"])
        #expect(command is LogTodayCommand)
    }

    @Test func logTodayCommandParses() throws {
        let command = try PresentCLI.parseAsRoot(["log", "today"])
        #expect(command is LogTodayCommand)
    }

    @Test func logWeekCommandParses() throws {
        let command = try PresentCLI.parseAsRoot(["log", "week"])
        #expect(command is LogWeekCommand)
    }

    @Test func logTodayCommandConfiguration() {
        #expect(LogTodayCommand.configuration.commandName == "today")
        #expect(LogTodayCommand.configuration.abstract == "Show today's logged sessions.")
    }

    @Test func logWeekCommandConfiguration() {
        #expect(LogWeekCommand.configuration.commandName == "week")
        #expect(LogWeekCommand.configuration.abstract == "Show this week's summary.")
    }

    // MARK: - ActivitiesCommand Parsing

    @Test func activitiesCommandConfiguration() {
        #expect(ActivitiesCommand.configuration.commandName == "activities")
        #expect(ActivitiesCommand.configuration.abstract == "Manage activities.")

        let subcommands = ActivitiesCommand.configuration.subcommands
        #expect(subcommands.count == 2)
    }

    @Test func activitiesDefaultSubcommandIsList() throws {
        let command = try PresentCLI.parseAsRoot(["activities"])
        #expect(command is ActivitiesListCommand)
    }

    @Test func activitiesListCommandParses() throws {
        let command = try PresentCLI.parseAsRoot(["activities", "list"])
        let list = try #require(command as? ActivitiesListCommand)
        #expect(list.includeArchived == false)
    }

    @Test func activitiesListIncludeArchivedFlag() throws {
        let command = try PresentCLI.parseAsRoot(["activities", "list", "--include-archived"])
        let list = try #require(command as? ActivitiesListCommand)
        #expect(list.includeArchived == true)
    }

    @Test func activitiesArchiveCommandParsesId() throws {
        let command = try PresentCLI.parseAsRoot(["activities", "archive", "42"])
        let archive = try #require(command as? ActivitiesArchiveCommand)
        #expect(archive.id == 42)
    }

    @Test func activitiesArchiveCommandParsesLargeId() throws {
        let command = try PresentCLI.parseAsRoot(["activities", "archive", "999999"])
        let archive = try #require(command as? ActivitiesArchiveCommand)
        #expect(archive.id == 999999)
    }

    @Test func activitiesArchiveRequiresId() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["activities", "archive"])
        }
    }

    @Test func activitiesArchiveRejectsNonIntegerId() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["activities", "archive", "abc"])
        }
    }

    @Test func activitiesListCommandConfiguration() {
        #expect(ActivitiesListCommand.configuration.commandName == "list")
        #expect(ActivitiesListCommand.configuration.abstract == "List active activities.")
    }

    @Test func activitiesArchiveCommandConfiguration() {
        #expect(ActivitiesArchiveCommand.configuration.commandName == "archive")
        #expect(ActivitiesArchiveCommand.configuration.abstract == "Archive an activity.")
    }

    // MARK: - Invalid Subcommand

    @Test func invalidSubcommandThrows() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["nonexistent"])
        }
    }

    // MARK: - StartCommand Configuration

    @Test func startCommandConfiguration() {
        #expect(StartCommand.configuration.commandName == "start")
        #expect(StartCommand.configuration.abstract == "Start a session for an activity.")
    }
}
