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
        #expect(subcommands.count == 5)

        let names = subcommands.map { $0.configuration.commandName ?? "" }
        #expect(names.contains("session"))
        #expect(names.contains("activity"))
        #expect(names.contains("tag"))
        #expect(names.contains("report"))
        #expect(names.contains("config"))
    }

    @Test func noDefaultSubcommand() throws {
        let command = try PresentCLI.parseAsRoot([])
        #expect(command is PresentCLI)
    }

    // MARK: - Session Group

    @Test func sessionGroupConfiguration() {
        #expect(SessionCommand.configuration.commandName == "session")
        let subcommands = SessionCommand.configuration.subcommands
        #expect(subcommands.count == 6)

        let names = subcommands.map { $0.configuration.commandName ?? "" }
        #expect(names.contains("start"))
        #expect(names.contains("add"))
        #expect(names.contains("get"))
        #expect(names.contains("list"))
        #expect(names.contains("delete"))
        #expect(names.contains("current"))
    }

    @Test func sessionRequiresSubcommand() throws {
        let command = try PresentCLI.parseAsRoot(["session"])
        #expect(command is SessionCommand)
    }

    // MARK: - Session Current Group

    @Test func sessionCurrentGroupConfiguration() {
        let subcommands = SessionCurrentCommand.configuration.subcommands
        #expect(subcommands.count == 5)

        let names = subcommands.map { $0.configuration.commandName ?? "" }
        #expect(names.contains("status"))
        #expect(names.contains("stop"))
        #expect(names.contains("pause"))
        #expect(names.contains("resume"))
        #expect(names.contains("cancel"))
    }

    @Test func sessionCurrentDefaultsToStatus() throws {
        let command = try PresentCLI.parseAsRoot(["session", "current"])
        #expect(command is SessionCurrentStatusCommand)
    }

    @Test func sessionCurrentStatusParses() throws {
        let command = try PresentCLI.parseAsRoot(["session", "current", "status"])
        #expect(command is SessionCurrentStatusCommand)
    }

    @Test func sessionCurrentStatusParsesTextOutput() throws {
        let command = try PresentCLI.parseAsRoot(["session", "current", "status", "-f", "text"])
        let status = try #require(command as? SessionCurrentStatusCommand)
        #expect(status.outputOptions.format == .text)
    }

    // MARK: - Session Get

    @Test func sessionGetParsesId() throws {
        let command = try PresentCLI.parseAsRoot(["session", "get", "42"])
        let get = try #require(command as? SessionGetCommand)
        #expect(get.id == 42)
    }

    @Test func sessionGetRequiresId() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["session", "get"])
        }
    }

    // MARK: - Session Start

    @Test func sessionStartParsesActivityName() throws {
        let command = try PresentCLI.parseAsRoot(["session", "start", "My Task"])
        let start = try #require(command as? SessionStartCommand)
        #expect(start.activityName == "My Task")
        #expect(start.type == "work")
        #expect(start.minutes == nil)
        #expect(start.breakMinutes == nil)
    }

    @Test func sessionStartParsesAllOptions() throws {
        let command = try PresentCLI.parseAsRoot([
            "session", "start", "Deep Work",
            "--type", "rhythm",
            "--minutes", "50",
            "--break-minutes", "10",
            "-f", "text"
        ])
        let start = try #require(command as? SessionStartCommand)
        #expect(start.activityName == "Deep Work")
        #expect(start.type == "rhythm")
        #expect(start.minutes == 50)
        #expect(start.breakMinutes == 10)
        #expect(start.outputOptions.format == .text)
    }

    @Test func sessionStartRequiresActivityName() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["session", "start"])
        }
    }

    @Test func sessionStartAcceptsActivityNameWithSpaces() throws {
        let command = try PresentCLI.parseAsRoot(["session", "start", "My Long Task Name"])
        let start = try #require(command as? SessionStartCommand)
        #expect(start.activityName == "My Long Task Name")
    }

    @Test func sessionStartDefaultTypeIsWork() throws {
        let command = try PresentCLI.parseAsRoot(["session", "start", "Task"])
        let start = try #require(command as? SessionStartCommand)
        #expect(start.type == "work")
    }

    @Test func sessionStartAcceptsAnyTypeString() throws {
        let command = try PresentCLI.parseAsRoot(["session", "start", "Task", "--type", "invalid"])
        let start = try #require(command as? SessionStartCommand)
        #expect(start.type == "invalid")
    }

    @Test func sessionStartConfiguration() {
        #expect(SessionStartCommand.configuration.commandName == "start")
        #expect(SessionStartCommand.configuration.abstract == "Start a session for an activity.")
    }

    // MARK: - Session Current Subcommands

    @Test func sessionCurrentStopParses() throws {
        let command = try PresentCLI.parseAsRoot(["session", "current", "stop"])
        #expect(command is SessionStopCommand)
    }

    @Test func sessionCurrentPauseParses() throws {
        let command = try PresentCLI.parseAsRoot(["session", "current", "pause"])
        #expect(command is SessionPauseCommand)
    }

    @Test func sessionCurrentResumeParses() throws {
        let command = try PresentCLI.parseAsRoot(["session", "current", "resume"])
        #expect(command is SessionResumeCommand)
    }

    @Test func sessionCurrentCancelParses() throws {
        let command = try PresentCLI.parseAsRoot(["session", "current", "cancel"])
        #expect(command is SessionCancelCommand)
    }

    // MARK: - Session List

    @Test func sessionListParses() throws {
        let command = try PresentCLI.parseAsRoot(["session", "list"])
        #expect(command is SessionListCommand)
    }

    @Test func sessionListParsesAllOptions() throws {
        let command = try PresentCLI.parseAsRoot([
            "session", "list",
            "--after", "2024-01-01",
            "--before", "2024-01-31",
            "--type", "work",
            "--activity", "Deep Work",
            "--page", "2",
            "-f", "text"
        ])
        let list = try #require(command as? SessionListCommand)
        #expect(list.after == "2024-01-01")
        #expect(list.before == "2024-01-31")
        #expect(list.type == "work")
        #expect(list.activity == "Deep Work")
        #expect(list.page == 2)
        #expect(list.outputOptions.format == .text)
    }

    @Test func sessionListDefaultPage() throws {
        let command = try PresentCLI.parseAsRoot(["session", "list"])
        let list = try #require(command as? SessionListCommand)
        #expect(list.page == 1)
    }

    // MARK: - Session Add

    @Test func sessionAddParsesRequiredArgs() throws {
        let command = try PresentCLI.parseAsRoot([
            "session", "add", "1",
            "--started-at", "2026-01-15T09:00:00",
            "--ended-at", "2026-01-15T10:00:00"
        ])
        let add = try #require(command as? SessionAddCommand)
        #expect(add.activityId == 1)
        #expect(add.startedAt == "2026-01-15T09:00:00")
        #expect(add.endedAt == "2026-01-15T10:00:00")
        #expect(add.type == "work")
        #expect(add.minutes == nil)
        #expect(add.breakMinutes == nil)
    }

    @Test func sessionAddParsesAllOptions() throws {
        let command = try PresentCLI.parseAsRoot([
            "session", "add", "5",
            "--started-at", "2026-01-15T09:00:00",
            "--ended-at", "2026-01-15T09:25:00",
            "--type", "rhythm",
            "--minutes", "25",
            "--break-minutes", "5",
            "-f", "text"
        ])
        let add = try #require(command as? SessionAddCommand)
        #expect(add.activityId == 5)
        #expect(add.type == "rhythm")
        #expect(add.minutes == 25)
        #expect(add.breakMinutes == 5)
        #expect(add.outputOptions.format == .text)
    }

    @Test func sessionAddRequiresActivityId() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["session", "add"])
        }
    }

    @Test func sessionAddRequiresTimestamps() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["session", "add", "1"])
        }
    }

    // MARK: - Activity Group

    @Test func activityGroupConfiguration() {
        #expect(ActivityCommand.configuration.commandName == "activity")
        let subcommands = ActivityCommand.configuration.subcommands
        #expect(subcommands.count == 10)

        let names = subcommands.map { $0.configuration.commandName ?? "" }
        #expect(names.contains("list"))
        #expect(names.contains("add"))
        #expect(names.contains("get"))
        #expect(names.contains("update"))
        #expect(names.contains("search"))
        #expect(names.contains("archive"))
        #expect(names.contains("unarchive"))
        #expect(names.contains("delete"))
        #expect(names.contains("note"))
        #expect(names.contains("tag"))
    }

    @Test func activityRequiresSubcommand() throws {
        let command = try PresentCLI.parseAsRoot(["activity"])
        #expect(command is ActivityCommand)
    }

    @Test func activityListParses() throws {
        let command = try PresentCLI.parseAsRoot(["activity", "list"])
        _ = try #require(command as? ActivityListCommand)
    }

    @Test func activityListTextOutput() throws {
        let command = try PresentCLI.parseAsRoot(["activity", "list", "-f", "text"])
        let list = try #require(command as? ActivityListCommand)
        #expect(list.outputOptions.format == .text)
    }

    @Test func activityListCsvOutput() throws {
        let command = try PresentCLI.parseAsRoot(["activity", "list", "-f", "csv"])
        let list = try #require(command as? ActivityListCommand)
        #expect(list.outputOptions.format == .csv)
    }

    @Test func activityAddParsesName() throws {
        let command = try PresentCLI.parseAsRoot(["activity", "add", "New Task"])
        let add = try #require(command as? ActivityAddCommand)
        #expect(add.name == "New Task")
        #expect(add.link == nil)
        #expect(add.externalId == nil)
    }

    @Test func activityAddParsesAllOptions() throws {
        let command = try PresentCLI.parseAsRoot([
            "activity", "add", "Task",
            "--link", "https://example.com",
            "--external-id", "EXT-123"
        ])
        let add = try #require(command as? ActivityAddCommand)
        #expect(add.name == "Task")
        #expect(add.link == "https://example.com")
        #expect(add.externalId == "EXT-123")
    }

    @Test func activityAddRequiresName() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["activity", "add"])
        }
    }

    @Test func activityGetParsesId() throws {
        let command = try PresentCLI.parseAsRoot(["activity", "get", "42"])
        let get = try #require(command as? ActivityGetCommand)
        #expect(get.id == 42)
    }

    @Test func activityGetRequiresId() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["activity", "get"])
        }
    }

    @Test func activityUpdateParsesIdAndTitle() throws {
        let command = try PresentCLI.parseAsRoot(["activity", "update", "42", "--title", "New Name"])
        let update = try #require(command as? ActivityUpdateCommand)
        #expect(update.id == 42)
        #expect(update.title == "New Name")
    }

    @Test func activityUpdateParsesAllOptions() throws {
        let command = try PresentCLI.parseAsRoot([
            "activity", "update", "42",
            "--title", "New Name",
            "--link", "https://example.com",
            "--external-id", "EXT-456"
        ])
        let update = try #require(command as? ActivityUpdateCommand)
        #expect(update.id == 42)
        #expect(update.title == "New Name")
        #expect(update.link == "https://example.com")
        #expect(update.externalId == "EXT-456")
    }

    @Test func activityUpdateRequiresId() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["activity", "update"])
        }
    }

    @Test func activitySearchParsesQuery() throws {
        let command = try PresentCLI.parseAsRoot(["activity", "search", "deep work"])
        let search = try #require(command as? ActivitySearchCommand)
        #expect(search.query == "deep work")
    }

    @Test func activityArchiveParsesId() throws {
        let command = try PresentCLI.parseAsRoot(["activity", "archive", "42"])
        let archive = try #require(command as? ActivityArchiveCommand)
        #expect(archive.id == 42)
    }

    @Test func activityUnarchiveParsesId() throws {
        let command = try PresentCLI.parseAsRoot(["activity", "unarchive", "42"])
        let unarchive = try #require(command as? ActivityUnarchiveCommand)
        #expect(unarchive.id == 42)
    }

    @Test func activityDeleteParsesId() throws {
        let command = try PresentCLI.parseAsRoot(["activity", "delete", "42"])
        let delete = try #require(command as? ActivityDeleteCommand)
        #expect(delete.id == 42)
    }

    @Test func activityArchiveRejectsNonIntegerId() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["activity", "archive", "abc"])
        }
    }

    // MARK: - Activity Note

    @Test func activityNoteParsesText() throws {
        let command = try PresentCLI.parseAsRoot(["activity", "note", "This is my note"])
        let note = try #require(command as? ActivityNoteCommand)
        #expect(note.text == "This is my note")
        #expect(note.id == nil)
    }

    @Test func activityNoteParsesIdOption() throws {
        let command = try PresentCLI.parseAsRoot(["activity", "note", "My note", "--id", "5"])
        let note = try #require(command as? ActivityNoteCommand)
        #expect(note.text == "My note")
        #expect(note.id == 5)
    }

    @Test func activityNoteRequiresText() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["activity", "note"])
        }
    }

    // MARK: - Activity Tag Group

    @Test func activityTagGroupConfiguration() {
        let subcommands = ActivityTagCommand.configuration.subcommands
        #expect(subcommands.count == 4)

        let names = subcommands.map { $0.configuration.commandName ?? "" }
        #expect(names.contains("add"))
        #expect(names.contains("remove"))
        #expect(names.contains("set"))
        #expect(names.contains("list"))
    }

    @Test func activityTagAddParsesArguments() throws {
        let command = try PresentCLI.parseAsRoot(["activity", "tag", "add", "1", "2"])
        let add = try #require(command as? ActivityTagAddCommand)
        #expect(add.activityId == 1)
        #expect(add.tagId == 2)
    }

    @Test func activityTagRemoveParsesArguments() throws {
        let command = try PresentCLI.parseAsRoot(["activity", "tag", "remove", "1", "2"])
        let remove = try #require(command as? ActivityTagRemoveCommand)
        #expect(remove.activityId == 1)
        #expect(remove.tagId == 2)
    }

    @Test func activityTagSetParsesArguments() throws {
        let command = try PresentCLI.parseAsRoot(["activity", "tag", "set", "1", "2", "3"])
        let set = try #require(command as? ActivityTagSetCommand)
        #expect(set.activityId == 1)
        #expect(set.tagIds == [2, 3])
    }

    @Test func activityTagSetEmptyTags() throws {
        let command = try PresentCLI.parseAsRoot(["activity", "tag", "set", "1"])
        let set = try #require(command as? ActivityTagSetCommand)
        #expect(set.activityId == 1)
        #expect(set.tagIds.isEmpty)
    }

    @Test func activityTagListParsesArguments() throws {
        let command = try PresentCLI.parseAsRoot(["activity", "tag", "list", "1"])
        let list = try #require(command as? ActivityTagListCommand)
        #expect(list.activityId == 1)
    }

    @Test func activityTagRequiresSubcommand() throws {
        let command = try PresentCLI.parseAsRoot(["activity", "tag"])
        #expect(command is ActivityTagCommand)
    }

    // MARK: - Tag Group

    @Test func tagGroupConfiguration() {
        #expect(TagCommand.configuration.commandName == "tag")
        let subcommands = TagCommand.configuration.subcommands
        #expect(subcommands.count == 5)

        let names = subcommands.map { $0.configuration.commandName ?? "" }
        #expect(names.contains("list"))
        #expect(names.contains("add"))
        #expect(names.contains("get"))
        #expect(names.contains("update"))
        #expect(names.contains("delete"))
    }

    @Test func tagRequiresSubcommand() throws {
        let command = try PresentCLI.parseAsRoot(["tag"])
        #expect(command is TagCommand)
    }

    @Test func tagAddParsesName() throws {
        let command = try PresentCLI.parseAsRoot(["tag", "add", "urgent"])
        let add = try #require(command as? TagAddCommand)
        #expect(add.name == "urgent")
    }

    @Test func tagAddRequiresName() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["tag", "add"])
        }
    }

    @Test func tagGetParsesId() throws {
        let command = try PresentCLI.parseAsRoot(["tag", "get", "3"])
        let get = try #require(command as? TagGetCommand)
        #expect(get.id == 3)
    }

    @Test func tagGetRequiresId() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["tag", "get"])
        }
    }

    @Test func tagUpdateParsesIdAndName() throws {
        let command = try PresentCLI.parseAsRoot(["tag", "update", "3", "--name", "critical"])
        let update = try #require(command as? TagUpdateCommand)
        #expect(update.id == 3)
        #expect(update.name == "critical")
    }

    @Test func tagUpdateRequiresName() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["tag", "update", "3"])
        }
    }

    @Test func tagDeleteParsesId() throws {
        let command = try PresentCLI.parseAsRoot(["tag", "delete", "3"])
        let delete = try #require(command as? TagDeleteCommand)
        #expect(delete.id == 3)
    }

    // MARK: - Report (Leaf Command)

    @Test func reportConfiguration() {
        #expect(ReportCommand.configuration.commandName == "report")
        #expect(ReportCommand.configuration.subcommands.isEmpty)
    }

    @Test func reportDefaultsToToday() throws {
        let command = try PresentCLI.parseAsRoot(["report"])
        let report = try #require(command as? ReportCommand)
        #expect(report.after == nil)
        #expect(report.before == nil)
    }

    @Test func reportParsesDateRange() throws {
        let command = try PresentCLI.parseAsRoot([
            "report", "--after", "2024-01-01", "--before", "2024-01-31"
        ])
        let report = try #require(command as? ReportCommand)
        #expect(report.after == "2024-01-01")
        #expect(report.before == "2024-01-31")
    }

    @Test func reportTextOutput() throws {
        let command = try PresentCLI.parseAsRoot(["report", "-f", "text"])
        let report = try #require(command as? ReportCommand)
        #expect(report.outputOptions.format == .text)
    }

    @Test func reportCsvOutput() throws {
        let command = try PresentCLI.parseAsRoot(["report", "-f", "csv"])
        let report = try #require(command as? ReportCommand)
        #expect(report.outputOptions.format == .csv)
    }

    // MARK: - Config Group

    @Test func configGroupConfiguration() {
        #expect(ConfigCommand.configuration.commandName == "config")
        let subcommands = ConfigCommand.configuration.subcommands
        #expect(subcommands.count == 3)

        let names = subcommands.map { $0.configuration.commandName ?? "" }
        #expect(names.contains("list"))
        #expect(names.contains("get"))
        #expect(names.contains("set"))
    }

    @Test func configRequiresSubcommand() throws {
        let command = try PresentCLI.parseAsRoot(["config"])
        #expect(command is ConfigCommand)
    }

    @Test func configGetParsesKey() throws {
        let command = try PresentCLI.parseAsRoot(["config", "get", "soundEffectsEnabled"])
        let get = try #require(command as? ConfigGetCommand)
        #expect(get.key == "soundEffectsEnabled")
    }

    @Test func configSetParsesKeyValue() throws {
        let command = try PresentCLI.parseAsRoot(["config", "set", "soundEffectsEnabled", "0"])
        let set = try #require(command as? ConfigSetCommand)
        #expect(set.key == "soundEffectsEnabled")
        #expect(set.value == "0")
    }

    @Test func configGetRequiresKey() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["config", "get"])
        }
    }

    @Test func configSetRequiresKeyAndValue() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["config", "set", "key"])
        }
    }

    // MARK: - Output Format

    @Test func outputFormatDefaultsToJSON() throws {
        let command = try PresentCLI.parseAsRoot(["session", "current", "status"])
        let status = try #require(command as? SessionCurrentStatusCommand)
        #expect(status.outputOptions.format == .json)
    }

    @Test func outputFormatShortFlag() throws {
        let command = try PresentCLI.parseAsRoot(["session", "current", "status", "-f", "text"])
        let status = try #require(command as? SessionCurrentStatusCommand)
        #expect(status.outputOptions.format == .text)
    }

    @Test func outputFormatLongFlag() throws {
        let command = try PresentCLI.parseAsRoot(["session", "current", "status", "--format", "csv"])
        let status = try #require(command as? SessionCurrentStatusCommand)
        #expect(status.outputOptions.format == .csv)
    }

    @Test func invalidOutputFormatThrows() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["session", "current", "status", "-f", "xml"])
        }
    }

    // MARK: - --field Option

    @Test func fieldOptionParses() throws {
        let command = try PresentCLI.parseAsRoot(["session", "current", "status", "--field", "state"])
        let status = try #require(command as? SessionCurrentStatusCommand)
        #expect(status.outputOptions.field == "state")
    }

    @Test func fieldOptionDefaultsToNil() throws {
        let command = try PresentCLI.parseAsRoot(["session", "current", "status"])
        let status = try #require(command as? SessionCurrentStatusCommand)
        #expect(status.outputOptions.field == nil)
    }

    @Test func fieldOptionCombinesWithTextOutput() throws {
        let command = try PresentCLI.parseAsRoot(["session", "current", "status", "--field", "elapsed", "-f", "text"])
        let status = try #require(command as? SessionCurrentStatusCommand)
        #expect(status.outputOptions.field == "elapsed")
        #expect(status.outputOptions.format == .text)
    }

    @Test func fieldOptionOnDifferentCommands() throws {
        let actCmd = try PresentCLI.parseAsRoot(["activity", "get", "1", "--field", "title"])
        let actGet = try #require(actCmd as? ActivityGetCommand)
        #expect(actGet.outputOptions.field == "title")

        let tagCmd = try PresentCLI.parseAsRoot(["tag", "add", "urgent", "--field", "id"])
        let tagAdd = try #require(tagCmd as? TagAddCommand)
        #expect(tagAdd.outputOptions.field == "id")

        let reportCmd = try PresentCLI.parseAsRoot(["report", "--field", "sessionCount"])
        let report = try #require(reportCmd as? ReportCommand)
        #expect(report.outputOptions.field == "sessionCount")
    }

    // MARK: - Invalid Subcommand

    @Test func invalidSubcommandThrows() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["nonexistent"])
        }
    }

    @Test func invalidSessionSubcommandThrows() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["session", "nonexistent"])
        }
    }
}
