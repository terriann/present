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
        #expect(subcommands.count == 8)

        let names = subcommands.map { $0.configuration.commandName ?? "" }
        #expect(names.contains("status"))
        #expect(names.contains("get"))
        #expect(names.contains("start"))
        #expect(names.contains("stop"))
        #expect(names.contains("pause"))
        #expect(names.contains("resume"))
        #expect(names.contains("cancel"))
        #expect(names.contains("search"))
    }

    @Test func sessionRequiresSubcommand() throws {
        let command = try PresentCLI.parseAsRoot(["session"])
        #expect(command is SessionCommand)
    }

    @Test func sessionStatusParses() throws {
        let command = try PresentCLI.parseAsRoot(["session", "status"])
        #expect(command is SessionStatusCommand)
    }

    @Test func sessionStatusParsesTextOutput() throws {
        let command = try PresentCLI.parseAsRoot(["session", "status", "-f", "text"])
        let status = try #require(command as? SessionStatusCommand)
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

    // MARK: - Session Stop / Pause / Resume / Cancel

    @Test func sessionStopParses() throws {
        let command = try PresentCLI.parseAsRoot(["session", "stop"])
        #expect(command is SessionStopCommand)
    }

    @Test func sessionStopConfiguration() {
        #expect(SessionStopCommand.configuration.commandName == "stop")
        #expect(SessionStopCommand.configuration.abstract == "Stop the current session.")
    }

    @Test func sessionPauseParses() throws {
        let command = try PresentCLI.parseAsRoot(["session", "pause"])
        #expect(command is SessionPauseCommand)
    }

    @Test func sessionPauseConfiguration() {
        #expect(SessionPauseCommand.configuration.commandName == "pause")
        #expect(SessionPauseCommand.configuration.abstract == "Pause the current session.")
    }

    @Test func sessionResumeParses() throws {
        let command = try PresentCLI.parseAsRoot(["session", "resume"])
        #expect(command is SessionResumeCommand)
    }

    @Test func sessionResumeConfiguration() {
        #expect(SessionResumeCommand.configuration.commandName == "resume")
        #expect(SessionResumeCommand.configuration.abstract == "Resume a paused session.")
    }

    @Test func sessionCancelParses() throws {
        let command = try PresentCLI.parseAsRoot(["session", "cancel"])
        #expect(command is SessionCancelCommand)
    }

    @Test func sessionCancelConfiguration() {
        #expect(SessionCancelCommand.configuration.commandName == "cancel")
        #expect(SessionCancelCommand.configuration.abstract == "Cancel the current session without logging it.")
    }

    // MARK: - Session Search

    @Test func sessionSearchParses() throws {
        let command = try PresentCLI.parseAsRoot(["session", "search"])
        #expect(command is SessionSearchCommand)
    }

    @Test func sessionSearchParsesAllOptions() throws {
        let command = try PresentCLI.parseAsRoot([
            "session", "search",
            "--after", "2024-01-01",
            "--before", "2024-01-31",
            "--type", "work",
            "--activity", "Deep Work",
            "--page", "2",
            "-f", "text"
        ])
        let search = try #require(command as? SessionSearchCommand)
        #expect(search.after == "2024-01-01")
        #expect(search.before == "2024-01-31")
        #expect(search.type == "work")
        #expect(search.activity == "Deep Work")
        #expect(search.page == 2)
        #expect(search.outputOptions.format == .text)
    }

    @Test func sessionSearchDefaultPage() throws {
        let command = try PresentCLI.parseAsRoot(["session", "search"])
        let search = try #require(command as? SessionSearchCommand)
        #expect(search.page == 1)
    }

    // MARK: - Activity Group

    @Test func activityGroupConfiguration() {
        #expect(ActivityCommand.configuration.commandName == "activity")
        let subcommands = ActivityCommand.configuration.subcommands
        #expect(subcommands.count == 11)

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
        #expect(names.contains("untag"))
    }

    @Test func activityRequiresSubcommand() throws {
        let command = try PresentCLI.parseAsRoot(["activity"])
        #expect(command is ActivityCommand)
    }

    @Test func activityListParses() throws {
        let command = try PresentCLI.parseAsRoot(["activity", "list"])
        let list = try #require(command as? ActivityListCommand)
        #expect(list.includeArchived == false)
    }

    @Test func activityListIncludeArchivedFlag() throws {
        let command = try PresentCLI.parseAsRoot(["activity", "list", "--include-archived"])
        let list = try #require(command as? ActivityListCommand)
        #expect(list.includeArchived == true)
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

    // MARK: - Activity Tag / Untag

    @Test func activityTagParsesArguments() throws {
        let command = try PresentCLI.parseAsRoot(["activity", "tag", "1", "2"])
        let tag = try #require(command as? ActivityTagCommand)
        #expect(tag.activityId == 1)
        #expect(tag.tagId == 2)
    }

    @Test func activityTagRequiresArguments() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["activity", "tag"])
        }
    }

    @Test func activityUntagParsesArguments() throws {
        let command = try PresentCLI.parseAsRoot(["activity", "untag", "1", "2"])
        let untag = try #require(command as? ActivityUntagCommand)
        #expect(untag.activityId == 1)
        #expect(untag.tagId == 2)
    }

    @Test func activityUntagRequiresArguments() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["activity", "untag"])
        }
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

    // MARK: - Report Group

    @Test func reportGroupConfiguration() {
        #expect(ReportCommand.configuration.commandName == "report")
        let subcommands = ReportCommand.configuration.subcommands
        #expect(subcommands.count == 4)

        let names = subcommands.map { $0.configuration.commandName ?? "" }
        #expect(names.contains("today"))
        #expect(names.contains("week"))
        #expect(names.contains("month"))
        #expect(names.contains("export"))
    }

    @Test func reportRequiresSubcommand() throws {
        let command = try PresentCLI.parseAsRoot(["report"])
        #expect(command is ReportCommand)
    }

    @Test func reportTodayParses() throws {
        let command = try PresentCLI.parseAsRoot(["report", "today"])
        #expect(command is ReportTodayCommand)
    }

    @Test func reportWeekParses() throws {
        let command = try PresentCLI.parseAsRoot(["report", "week"])
        #expect(command is ReportWeekCommand)
    }

    @Test func reportMonthParses() throws {
        let command = try PresentCLI.parseAsRoot(["report", "month"])
        #expect(command is ReportMonthCommand)
    }

    @Test func reportExportParses() throws {
        let command = try PresentCLI.parseAsRoot(["report", "export"])
        #expect(command is ReportExportCommand)
    }

    @Test func reportExportParsesDateRange() throws {
        let command = try PresentCLI.parseAsRoot([
            "report", "export", "--from", "2024-01-01", "--to", "2024-01-31"
        ])
        let export = try #require(command as? ReportExportCommand)
        #expect(export.from == "2024-01-01")
        #expect(export.to == "2024-01-31")
    }

    @Test func reportTodayTextOutput() throws {
        let command = try PresentCLI.parseAsRoot(["report", "today", "-f", "text"])
        let today = try #require(command as? ReportTodayCommand)
        #expect(today.outputOptions.format == .text)
    }

    @Test func reportTodayCsvOutput() throws {
        let command = try PresentCLI.parseAsRoot(["report", "today", "-f", "csv"])
        let today = try #require(command as? ReportTodayCommand)
        #expect(today.outputOptions.format == .csv)
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
        let command = try PresentCLI.parseAsRoot(["session", "status"])
        let status = try #require(command as? SessionStatusCommand)
        #expect(status.outputOptions.format == .json)
    }

    @Test func outputFormatShortFlag() throws {
        let command = try PresentCLI.parseAsRoot(["session", "status", "-f", "text"])
        let status = try #require(command as? SessionStatusCommand)
        #expect(status.outputOptions.format == .text)
    }

    @Test func outputFormatLongFlag() throws {
        let command = try PresentCLI.parseAsRoot(["session", "status", "--format", "csv"])
        let status = try #require(command as? SessionStatusCommand)
        #expect(status.outputOptions.format == .csv)
    }

    @Test func invalidOutputFormatThrows() {
        #expect(throws: (any Error).self) {
            try PresentCLI.parseAsRoot(["session", "status", "-f", "xml"])
        }
    }

    // MARK: - --field Option

    @Test func fieldOptionParses() throws {
        let command = try PresentCLI.parseAsRoot(["session", "status", "--field", "state"])
        let status = try #require(command as? SessionStatusCommand)
        #expect(status.outputOptions.field == "state")
    }

    @Test func fieldOptionDefaultsToNil() throws {
        let command = try PresentCLI.parseAsRoot(["session", "status"])
        let status = try #require(command as? SessionStatusCommand)
        #expect(status.outputOptions.field == nil)
    }

    @Test func fieldOptionCombinesWithTextOutput() throws {
        let command = try PresentCLI.parseAsRoot(["session", "status", "--field", "elapsed", "-f", "text"])
        let status = try #require(command as? SessionStatusCommand)
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

        let reportCmd = try PresentCLI.parseAsRoot(["report", "today", "--field", "sessionCount"])
        let reportToday = try #require(reportCmd as? ReportTodayCommand)
        #expect(reportToday.outputOptions.field == "sessionCount")
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
