import Testing
import Foundation
@testable import PresentCLI
@testable import PresentCore

/// Tests that verify CLI command output format (JSON, text, CSV) and --field extraction.
/// Uses stdout capture to assert on actual command output strings.
/// Output format tests share CLIServiceFactory.serviceOverride with CLIIntegrationTests.
/// Both are nested inside CLIServiceOverrideTests (serialized) to prevent races.
/// See CLIIntegrationTests.swift for the parent suite.
extension CLIServiceOverrideTests {

    @Suite("CLI Output Format Tests")
    struct OutputFormatTests {

    // MARK: - Activity List

    @Test func activityListJSON() async throws {
        try await CLIServiceOverrideTests.withTestService { service in
            _ = try await service.createActivity(CreateActivityInput(title: "Alpha"))
            _ = try await service.createActivity(CreateActivityInput(title: "Beta"))

            let output = try await captureStdout {
                var cmd = try ActivityListCommand.parse(["-f", "json"])
                try await cmd.run()
            }

            // Should be valid JSON with pagination
            let data = try #require(output.data(using: .utf8))
            let json = try JSONSerialization.jsonObject(with: data)
            let dict = try #require(json as? [String: Any])
            #expect(dict["page"] as? Int == 1)
            #expect(dict["totalCount"] as? Int ?? 0 >= 2)
            let array = try #require(dict["activities"] as? [[String: Any]])
            #expect(array.count >= 2)

            // Check field names
            let first = try #require(array.first)
            #expect(first["id"] != nil)
            #expect(first["title"] != nil)
            #expect(first["isArchived"] != nil)
        }
    }

    @Test func activityListText() async throws {
        try await CLIServiceOverrideTests.withTestService { service in
            _ = try await service.createActivity(CreateActivityInput(title: "Text Test"))

            let output = try await captureStdout {
                var cmd = try ActivityListCommand.parse(["-f", "text"])
                try await cmd.run()
            }

            #expect(output.contains("Text Test"))
        }
    }

    @Test func activityListCSV() async throws {
        try await CLIServiceOverrideTests.withTestService { service in
            _ = try await service.createActivity(CreateActivityInput(title: "CSV Test"))

            let output = try await captureStdout {
                var cmd = try ActivityListCommand.parse(["-f", "csv"])
                try await cmd.run()
            }

            let lines = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
            #expect(lines.first == "ID,Title,Archived,External ID,Link")
            #expect(lines.count >= 2)
            #expect(lines.last?.contains("CSV Test") == true)
        }
    }

    @Test func activityListCSVEscapesSpecialCharacters() async throws {
        try await CLIServiceOverrideTests.withTestService { service in
            _ = try await service.createActivity(CreateActivityInput(
                title: "Say \"hello\", world"
            ))

            let output = try await captureStdout {
                var cmd = try ActivityListCommand.parse(["-f", "csv"])
                try await cmd.run()
            }

            // Title with quotes and commas should be RFC 4180 escaped
            #expect(output.contains("\"Say \"\"hello\"\", world\""))
        }
    }

    // MARK: - Activity Get with --field

    @Test func activityGetFieldExtractsTitle() async throws {
        try await CLIServiceOverrideTests.withTestService { service in
            let activity = try await service.createActivity(CreateActivityInput(title: "Field Test"))
            let id = try #require(activity.id)

            let output = try await captureStdout {
                var cmd = try ActivityGetCommand.parse(["\(id)", "--field", "title"])
                try await cmd.run()
            }

            #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "Field Test")
        }
    }

    @Test func activityGetFieldExtractsId() async throws {
        try await CLIServiceOverrideTests.withTestService { service in
            let activity = try await service.createActivity(CreateActivityInput(title: "ID Test"))
            let id = try #require(activity.id)

            let output = try await captureStdout {
                var cmd = try ActivityGetCommand.parse(["\(id)", "--field", "id"])
                try await cmd.run()
            }

            #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "\(id)")
        }
    }

    // MARK: - Session Current Status

    @Test func sessionCurrentStatusJSON() async throws {
        try await CLIServiceOverrideTests.withTestService { service in
            let activity = try await service.createActivity(CreateActivityInput(title: "Status JSON"))
            let actId = try #require(activity.id)
            _ = try await service.startSession(activityId: actId, type: .work)

            let output = try await captureStdout {
                var cmd = try SessionCurrentStatusCommand.parse(["-f", "json"])
                try await cmd.run()
            }

            let data = try #require(output.data(using: .utf8))
            let json = try JSONSerialization.jsonObject(with: data)
            let dict = try #require(json as? [String: Any])
            #expect(dict["active"] as? Bool == true)
            #expect(dict["elapsedSeconds"] != nil)
            #expect(dict["sessionId"] != nil)
        }
    }

    @Test func sessionCurrentStatusText() async throws {
        try await CLIServiceOverrideTests.withTestService { service in
            let activity = try await service.createActivity(CreateActivityInput(title: "Status Text"))
            let actId = try #require(activity.id)
            _ = try await service.startSession(activityId: actId, type: .work)

            let output = try await captureStdout {
                var cmd = try SessionCurrentStatusCommand.parse(["-f", "text"])
                try await cmd.run()
            }

            #expect(output.contains("Active: Status Text"))
            #expect(output.contains("Type:"))
            #expect(output.contains("Elapsed:"))
        }
    }

    @Test func sessionCurrentStatusNoSessionJSON() async throws {
        try await CLIServiceOverrideTests.withTestService { _ in
            let output = try await captureStdout {
                var cmd = try SessionCurrentStatusCommand.parse(["-f", "json"])
                try await cmd.run()
            }

            let data = try #require(output.data(using: .utf8))
            let json = try JSONSerialization.jsonObject(with: data)
            let dict = try #require(json as? [String: Any])
            #expect(dict["active"] as? Bool == false)
        }
    }

    @Test func sessionCurrentStatusNoSessionText() async throws {
        try await CLIServiceOverrideTests.withTestService { _ in
            let output = try await captureStdout {
                var cmd = try SessionCurrentStatusCommand.parse(["-f", "text"])
                try await cmd.run()
            }

            #expect(output.contains("No active session"))
        }
    }

    // MARK: - Session List

    @Test func sessionListJSON() async throws {
        try await CLIServiceOverrideTests.withTestService { service in
            let activity = try await service.createActivity(CreateActivityInput(title: "List JSON"))
            let actId = try #require(activity.id)
            _ = try await service.startSession(activityId: actId, type: .work)
            _ = try await service.stopSession()

            let today = DateFormatter()
            today.dateFormat = "yyyy-MM-dd"
            let dateStr = today.string(from: Date())

            let output = try await captureStdout {
                var cmd = try SessionListCommand.parse(["--after", dateStr, "-f", "json"])
                try await cmd.run()
            }

            let data = try #require(output.data(using: .utf8))
            let json = try JSONSerialization.jsonObject(with: data)
            let dict = try #require(json as? [String: Any])
            #expect(dict["page"] as? Int == 1)
            let sessions = try #require(dict["sessions"] as? [[String: Any]])
            #expect(sessions.count >= 1)
            #expect(sessions.first?["sessionId"] != nil)
            #expect(sessions.first?["activity"] != nil)
        }
    }

    @Test func sessionListCSV() async throws {
        try await CLIServiceOverrideTests.withTestService { service in
            let activity = try await service.createActivity(CreateActivityInput(title: "List CSV"))
            let actId = try #require(activity.id)
            _ = try await service.startSession(activityId: actId, type: .work)
            _ = try await service.stopSession()

            let today = DateFormatter()
            today.dateFormat = "yyyy-MM-dd"
            let dateStr = today.string(from: Date())

            let output = try await captureStdout {
                var cmd = try SessionListCommand.parse(["--after", dateStr, "-f", "csv"])
                try await cmd.run()
            }

            let lines = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
            #expect(lines.first == "Session ID,Activity,Type,State,Started At,Ended At,Duration (seconds)")
            #expect(lines.count >= 2)
        }
    }

    // MARK: - Report

    @Test func reportJSON() async throws {
        try await CLIServiceOverrideTests.withTestService { _ in
            let output = try await captureStdout {
                var cmd = try ReportCommand.parse(["-f", "json"])
                try await cmd.run()
            }

            let data = try #require(output.data(using: .utf8))
            let json = try JSONSerialization.jsonObject(with: data)
            let dict = try #require(json as? [String: Any])
            #expect(dict["totalSeconds"] != nil)
            #expect(dict["sessionCount"] != nil)
            #expect(dict["activities"] != nil)
        }
    }

    @Test func reportCSV() async throws {
        try await CLIServiceOverrideTests.withTestService { service in
            let activity = try await service.createActivity(CreateActivityInput(title: "Report CSV"))
            let actId = try #require(activity.id)
            let now = Date()
            let startedAt = try #require(Calendar.current.date(byAdding: .hour, value: -1, to: now))
            _ = try await service.createBackdatedSession(CreateBackdatedSessionInput(
                activityId: actId, sessionType: .work, startedAt: startedAt, endedAt: now
            ))

            let today = DateFormatter()
            today.dateFormat = "yyyy-MM-dd"
            let dateStr = today.string(from: now)

            let output = try await captureStdout {
                var cmd = try ReportCommand.parse(["--after", dateStr, "-f", "csv"])
                try await cmd.run()
            }

            let lines = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
            #expect(lines.first == "Activity,Total Seconds,Sessions")
            #expect(lines.count >= 2)
            #expect(output.contains("Report CSV"))
        }
    }

    // MARK: - Tag List

    @Test func tagListJSON() async throws {
        try await CLIServiceOverrideTests.withTestService { service in
            _ = try await service.createTag(name: "json-tag")

            let output = try await captureStdout {
                var cmd = try TagListCommand.parse(["-f", "json"])
                try await cmd.run()
            }

            let data = try #require(output.data(using: .utf8))
            let json = try JSONSerialization.jsonObject(with: data)
            let array = try #require(json as? [[String: Any]])
            #expect(array.contains { ($0["name"] as? String) == "json-tag" })
        }
    }

    @Test func tagListCSV() async throws {
        try await CLIServiceOverrideTests.withTestService { service in
            _ = try await service.createTag(name: "csv-tag")

            let output = try await captureStdout {
                var cmd = try TagListCommand.parse(["-f", "csv"])
                try await cmd.run()
            }

            let lines = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
            #expect(lines.first == "ID,Name")
            #expect(output.contains("csv-tag"))
        }
    }

    // MARK: - Config List

    @Test func configListJSON() async throws {
        try await CLIServiceOverrideTests.withTestService { _ in
            let output = try await captureStdout {
                var cmd = try ConfigListCommand.parse(["-f", "json"])
                try await cmd.run()
            }

            let data = try #require(output.data(using: .utf8))
            let json = try JSONSerialization.jsonObject(with: data)
            let array = try #require(json as? [[String: Any]])
            #expect(array.count > 0)
            #expect(array.first?["key"] != nil)
            #expect(array.first?["value"] != nil)
        }
    }

    @Test func configListCSV() async throws {
        try await CLIServiceOverrideTests.withTestService { _ in
            let output = try await captureStdout {
                var cmd = try ConfigListCommand.parse(["-f", "csv"])
                try await cmd.run()
            }

            let lines = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
            #expect(lines.first == "Key,Value")
            #expect(lines.count > 1)
        }
    }

    // MARK: - Activity List Pagination Output

    @Test func activityListPaginationJSON() async throws {
        try await CLIServiceOverrideTests.withTestService { service in
            _ = try await service.createActivity(CreateActivityInput(title: "Paginated"))

            let output = try await captureStdout {
                var cmd = try ActivityListCommand.parse(["-f", "json", "--page", "1"])
                try await cmd.run()
            }

            let data = try #require(output.data(using: .utf8))
            let json = try JSONSerialization.jsonObject(with: data)
            let dict = try #require(json as? [String: Any])
            #expect(dict["page"] as? Int == 1)
            #expect(dict["totalPages"] as? Int == 1)
            #expect(dict["totalCount"] as? Int ?? 0 >= 1)
            #expect(dict["activities"] != nil)
        }
    }

    @Test func activityListTextShowsPagination() async throws {
        try await CLIServiceOverrideTests.withTestService { service in
            _ = try await service.createActivity(CreateActivityInput(title: "Text Page"))

            let output = try await captureStdout {
                var cmd = try ActivityListCommand.parse(["-f", "text"])
                try await cmd.run()
            }

            #expect(output.contains("Activities (page"))
        }
    }

    // MARK: - Session List with Active Session Output

    @Test func sessionListJSONIncludesActiveSession() async throws {
        try await CLIServiceOverrideTests.withTestService { service in
            let activity = try await service.createActivity(CreateActivityInput(title: "Active Output"))
            let actId = try #require(activity.id)
            _ = try await service.startSession(activityId: actId, type: .work)

            let today = DateFormatter()
            today.dateFormat = "yyyy-MM-dd"
            let dateStr = today.string(from: Date())

            let output = try await captureStdout {
                var cmd = try SessionListCommand.parse(["--after", dateStr, "-f", "json"])
                try await cmd.run()
            }

            let data = try #require(output.data(using: .utf8))
            let json = try JSONSerialization.jsonObject(with: data)
            let dict = try #require(json as? [String: Any])
            let sessions = try #require(dict["sessions"] as? [[String: Any]])
            let hasRunning = sessions.contains { ($0["state"] as? String) == "running" }
            #expect(hasRunning)
        }
    }

    // MARK: - Report with Active Session Output

    @Test func reportJSONIncludesActiveSessionFlag() async throws {
        try await CLIServiceOverrideTests.withTestService { service in
            let activity = try await service.createActivity(CreateActivityInput(title: "Report Active"))
            let actId = try #require(activity.id)
            _ = try await service.startSession(activityId: actId, type: .work)

            try await Task.sleep(for: .milliseconds(50))

            let output = try await captureStdout {
                var cmd = try ReportCommand.parse(["-f", "json"])
                try await cmd.run()
            }

            let data = try #require(output.data(using: .utf8))
            let json = try JSONSerialization.jsonObject(with: data)
            let dict = try #require(json as? [String: Any])
            #expect(dict["includesActiveSession"] as? Bool == true)
            // totalSeconds may be 0 if session just started (Int truncation)
            #expect(dict["totalSeconds"] != nil)
        }
    }
    }
}
