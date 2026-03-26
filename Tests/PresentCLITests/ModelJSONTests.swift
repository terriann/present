import Testing
import Foundation
@testable import PresentCLI
@testable import PresentCore

@Suite("ModelJSON Tests")
struct ModelJSONTests {

    private let fixedDate = Date(timeIntervalSince1970: 1700000000) // 2023-11-14T22:13:20Z

    // MARK: - Activity JSON

    @Test func activityJSONDictIncludesAllFields() {
        let activity = Activity(
            id: 42, title: "Code Review", externalId: "TEAM-123",
            link: "https://example.com", notes: "Some notes",
            isArchived: false, isSystem: false,
            createdAt: fixedDate, updatedAt: fixedDate
        )
        let dict = activity.toJSONDict()

        #expect(dict["id"] as? Int64 == 42)
        #expect(dict["title"] as? String == "Code Review")
        #expect(dict["externalId"] as? String == "TEAM-123")
        #expect(dict["link"] as? String == "https://example.com")
        #expect(dict["notes"] as? String == "Some notes")
        #expect(dict["isArchived"] as? Bool == false)
        #expect(dict["isSystem"] as? Bool == false)
        // Top-level uses "id", not "activityId"
        #expect(dict["activityId"] == nil)
    }

    @Test func activityNestedDictUsesActivityIdKey() {
        let activity = Activity(id: 7, title: "Test", createdAt: fixedDate, updatedAt: fixedDate)
        let dict = activity.toNestedJSONDict()

        #expect(dict["activityId"] as? Int64 == 7)
        #expect(dict["id"] == nil)
    }

    @Test func activityJSONDictIncludesTags() {
        let activity = Activity(id: 1, title: "Test", createdAt: fixedDate, updatedAt: fixedDate)
        let tags = [Tag(id: 10, name: "urgent", createdAt: fixedDate, updatedAt: fixedDate)]
        let dict = activity.toJSONDict(tags: tags)

        let tagArray = dict["tags"] as? [[String: Any]]
        #expect(tagArray?.count == 1)
        #expect(tagArray?.first?["name"] as? String == "urgent")
    }

    @Test func activityTextFieldsOmitNilOptionals() {
        let activity = Activity(id: 1, title: "Test", createdAt: fixedDate, updatedAt: fixedDate)
        let fields = activity.toTextFields()

        #expect(fields["title"] == "Test")
        #expect(fields["externalId"] == nil)
        #expect(fields["link"] == nil)
        #expect(fields["notes"] == nil)
    }

    @Test func activityTextFieldsIncludeOptionals() {
        let activity = Activity(
            id: 1, title: "Test", externalId: "EXT-1",
            link: "https://example.com", notes: "Hello",
            createdAt: fixedDate, updatedAt: fixedDate
        )
        let fields = activity.toTextFields()

        #expect(fields["externalId"] == "EXT-1")
        #expect(fields["link"] == "https://example.com")
        #expect(fields["notes"] == "Hello")
    }

    // MARK: - Session JSON

    @Test func sessionJSONDictIncludesRequiredFields() {
        let session = Session(
            id: 99, activityId: 1, sessionType: .work,
            startedAt: fixedDate, state: .running,
            createdAt: fixedDate
        )
        let dict = session.toJSONDict()

        #expect(dict["sessionId"] as? Int64 == 99)
        #expect(dict["type"] as? String == "work")
        #expect(dict["state"] as? String == "running")
        #expect(dict["startedAt"] as? String != nil)
    }

    @Test func sessionJSONDictNestsActivity() {
        let session = Session(
            id: 1, activityId: 42, sessionType: .work,
            startedAt: fixedDate, state: .running, createdAt: fixedDate
        )
        let activity = Activity(id: 42, title: "Coding", createdAt: fixedDate, updatedAt: fixedDate)
        let dict = session.toJSONDict(activity: activity)

        let nested = dict["activity"] as? [String: Any]
        #expect(nested?["activityId"] as? Int64 == 42)
        #expect(nested?["title"] as? String == "Coding")
    }

    @Test func sessionJSONDictOmitsNilOptionals() {
        let session = Session(
            id: 1, activityId: 1, sessionType: .work,
            startedAt: fixedDate, state: .running, createdAt: fixedDate
        )
        let dict = session.toJSONDict()

        #expect(dict["endedAt"] == nil)
        #expect(dict["durationSeconds"] == nil)
        #expect(dict["timerMinutes"] == nil)
        #expect(dict["note"] == nil)
    }

    @Test func sessionJSONDictIncludesOptionals() {
        let endDate = fixedDate.addingTimeInterval(3600)
        let session = Session(
            id: 1, activityId: 1, sessionType: .timebound,
            startedAt: fixedDate, endedAt: endDate, durationSeconds: 3600,
            timerLengthMinutes: 60, state: .completed,
            note: "Done", link: "https://example.com", ticketId: "TICKET-1",
            createdAt: fixedDate
        )
        let dict = session.toJSONDict()

        #expect(dict["endedAt"] as? String != nil)
        #expect(dict["durationSeconds"] as? Int == 3600)
        #expect(dict["timerMinutes"] as? Int == 60)
        #expect(dict["note"] as? String == "Done")
        #expect(dict["link"] as? String == "https://example.com")
        #expect(dict["ticketId"] as? String == "TICKET-1")
    }

    @Test func sessionTextFieldsIncludeDuration() {
        let session = Session(
            id: 1, activityId: 1, sessionType: .work,
            startedAt: fixedDate, durationSeconds: 5400,
            state: .completed, createdAt: fixedDate
        )
        let fields = session.toTextFields()

        #expect(fields["durationSeconds"] == "5400")
        #expect(fields["duration"] != nil) // Formatted duration
    }

    // MARK: - Tag JSON

    @Test func tagJSONDictUsesIdKey() {
        let tag = Tag(id: 5, name: "focus", createdAt: fixedDate, updatedAt: fixedDate)
        let dict = tag.toJSONDict()

        #expect(dict["id"] as? Int64 == 5)
        #expect(dict["name"] as? String == "focus")
        #expect(dict["tagId"] == nil)
    }

    @Test func tagNestedDictUsesTagIdKey() {
        let tag = Tag(id: 5, name: "focus", createdAt: fixedDate, updatedAt: fixedDate)
        let dict = tag.toNestedJSONDict()

        #expect(dict["tagId"] as? Int64 == 5)
        #expect(dict["id"] == nil)
    }

    @Test func tagTextFieldsComplete() {
        let tag = Tag(id: 5, name: "focus", createdAt: fixedDate, updatedAt: fixedDate)
        let fields = tag.toTextFields()

        #expect(fields["id"] == "5")
        #expect(fields["name"] == "focus")
        #expect(fields["createdAt"] != nil)
        #expect(fields["updatedAt"] != nil)
    }

    // MARK: - Summary Types

    @Test func activitySummaryJSONDict() {
        let activity = Activity(id: 1, title: "Test", createdAt: fixedDate, updatedAt: fixedDate)
        let summary = ActivitySummary(activity: activity, totalSeconds: 7200, sessionCount: 3)
        let dict = summary.toJSONDict()

        #expect(dict["totalSeconds"] as? Int == 7200)
        #expect(dict["sessionCount"] as? Int == 3)
        let nested = dict["activity"] as? [String: Any]
        #expect(nested?["title"] as? String == "Test")
    }
}
