import Testing
import Foundation
@testable import PresentCore

/// Tests for `PresentService.externalIdSummary(from:to:includeArchived:)`.
///
/// Verifies grouping by effective external ID (COALESCE of session ticketId
/// and activity externalId), cross-midnight clamping, archive filtering,
/// sourceURL resolution, and pipe-separated activity name handling.
@Suite("External ID Summary Tests")
struct ExternalIdSummaryTests {

    private func makeService() throws -> PresentService {
        let dbManager = try DatabaseManager(inMemory: true)
        return PresentService(databasePool: dbManager.writer)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0, second: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute; c.second = second
        return Calendar.current.date(from: c)!
    }

    /// Helper: date range covering a single day (midnight to midnight).
    private func dayRange(year: Int, month: Int, day: Int) -> (from: Date, to: Date) {
        let from = makeDate(year: year, month: month, day: day, hour: 0, minute: 0, second: 0)
        let to = makeDate(year: year, month: month, day: day + 1, hour: 0, minute: 0, second: 0)
        return (from, to)
    }

    @discardableResult
    private func addSession(
        service: PresentService,
        activityId: Int64,
        start: Date,
        end: Date,
        link: String? = nil
    ) async throws -> Session {
        try await service.createBackdatedSession(CreateBackdatedSessionInput(
            activityId: activityId, startedAt: start, endedAt: end, link: link
        ))
    }

    // MARK: - Happy Path

    @Test func groupsByActivityExternalId() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(
            title: "Bug Fix", externalId: "PROJ-100"
        ))

        // Two sessions on the same activity with an externalId
        let range = dayRange(year: 2025, month: 6, day: 10)
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 6, day: 10, hour: 9),
            end: makeDate(year: 2025, month: 6, day: 10, hour: 11))
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 6, day: 10, hour: 14),
            end: makeDate(year: 2025, month: 6, day: 10, hour: 15))

        let results = try await service.externalIdSummary(
            from: range.from, to: range.to, includeArchived: false
        )

        #expect(results.count == 1)
        #expect(results[0].externalId == "PROJ-100")
        #expect(results[0].totalSeconds == 10800) // 3h
        #expect(results[0].sessionCount == 2)
        #expect(results[0].activityNames == ["Bug Fix"])
    }

    @Test func sessionsWithoutExternalIdAreExcluded() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "No Ticket"))

        let range = dayRange(year: 2025, month: 6, day: 10)
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 6, day: 10, hour: 9),
            end: makeDate(year: 2025, month: 6, day: 10, hour: 11))

        let results = try await service.externalIdSummary(
            from: range.from, to: range.to, includeArchived: false
        )

        #expect(results.isEmpty)
    }

    // MARK: - COALESCE: Session ticketId Takes Priority

    @Test func sessionTicketIdOverridesActivityExternalId() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(
            title: "Feature Work", externalId: "ACTIVITY-1"
        ))

        let range = dayRange(year: 2025, month: 6, day: 10)

        // Session with a Linear link — ticketId will be extracted as "FEAT-42"
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 6, day: 10, hour: 9),
            end: makeDate(year: 2025, month: 6, day: 10, hour: 10),
            link: "https://linear.app/team/issue/FEAT-42")

        // Session without a link — falls back to activity externalId "ACTIVITY-1"
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 6, day: 10, hour: 11),
            end: makeDate(year: 2025, month: 6, day: 10, hour: 12))

        let results = try await service.externalIdSummary(
            from: range.from, to: range.to, includeArchived: false
        )

        // Should produce two groups: FEAT-42 (from ticketId) and ACTIVITY-1 (from externalId)
        let ids = Set(results.map(\.externalId))
        #expect(ids == ["FEAT-42", "ACTIVITY-1"])

        let feat42 = results.first { $0.externalId == "FEAT-42" }
        #expect(feat42?.totalSeconds == 3600) // 1h
        #expect(feat42?.sessionCount == 1)

        let activity1 = results.first { $0.externalId == "ACTIVITY-1" }
        #expect(activity1?.totalSeconds == 3600) // 1h
        #expect(activity1?.sessionCount == 1)
    }

    // MARK: - Pipe-Separated Activity Names

    @Test func activityTitlesWithCommasArePreserved() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(
            title: "Fix bugs, write tests", externalId: "PROJ-200"
        ))

        let range = dayRange(year: 2025, month: 6, day: 10)
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 6, day: 10, hour: 9),
            end: makeDate(year: 2025, month: 6, day: 10, hour: 10))

        let results = try await service.externalIdSummary(
            from: range.from, to: range.to, includeArchived: false
        )

        #expect(results.count == 1)
        // The full title including comma should survive pipe separation
        #expect(results[0].activityNames == ["Fix bugs, write tests"])
    }

    // MARK: - Multiple Activities Contributing to Same External ID

    @Test func multipleActivitiesShareExternalId() async throws {
        let service = try makeService()
        let a1 = try await service.createActivity(CreateActivityInput(
            title: "Backend Work", externalId: "PROJ-300"
        ))
        let a2 = try await service.createActivity(CreateActivityInput(
            title: "Frontend Work", externalId: "PROJ-300"
        ))

        let range = dayRange(year: 2025, month: 6, day: 10)
        try await addSession(service: service, activityId: a1.id!,
            start: makeDate(year: 2025, month: 6, day: 10, hour: 9),
            end: makeDate(year: 2025, month: 6, day: 10, hour: 11))
        try await addSession(service: service, activityId: a2.id!,
            start: makeDate(year: 2025, month: 6, day: 10, hour: 14),
            end: makeDate(year: 2025, month: 6, day: 10, hour: 15))

        let results = try await service.externalIdSummary(
            from: range.from, to: range.to, includeArchived: false
        )

        #expect(results.count == 1)
        #expect(results[0].externalId == "PROJ-300")
        #expect(results[0].totalSeconds == 10800) // 3h
        #expect(results[0].sessionCount == 2)
        // Both activity titles should appear
        #expect(Set(results[0].activityNames) == Set(["Backend Work", "Frontend Work"]))
    }

    // MARK: - Cross-Midnight Clamping

    @Test func crossMidnightSessionClampedToDateRange() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(
            title: "Late Night", externalId: "PROJ-400"
        ))

        // Session from 10 PM to 2 AM (4h total: 2h on day 10, 2h on day 11)
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 6, day: 10, hour: 22),
            end: makeDate(year: 2025, month: 6, day: 11, hour: 2))

        // Query for day 10 only
        let day10 = dayRange(year: 2025, month: 6, day: 10)
        let resultsDay10 = try await service.externalIdSummary(
            from: day10.from, to: day10.to, includeArchived: false
        )

        #expect(resultsDay10.count == 1)
        #expect(resultsDay10[0].totalSeconds == 7200) // 2h (10 PM to midnight)

        // Query for day 11 only
        let day11 = dayRange(year: 2025, month: 6, day: 11)
        let resultsDay11 = try await service.externalIdSummary(
            from: day11.from, to: day11.to, includeArchived: false
        )

        #expect(resultsDay11.count == 1)
        #expect(resultsDay11[0].totalSeconds == 7200) // 2h (midnight to 2 AM)
    }

    // MARK: - Archived Activity Filtering

    @Test func archivedActivityExcludedByDefault() async throws {
        let service = try makeService()
        let active = try await service.createActivity(CreateActivityInput(
            title: "Active", externalId: "PROJ-500"
        ))
        let archived = try await service.createActivity(CreateActivityInput(
            title: "Archived", externalId: "PROJ-501"
        ))

        let range = dayRange(year: 2025, month: 6, day: 10)
        try await addSession(service: service, activityId: active.id!,
            start: makeDate(year: 2025, month: 6, day: 10, hour: 9),
            end: makeDate(year: 2025, month: 6, day: 10, hour: 10))
        try await addSession(service: service, activityId: archived.id!,
            start: makeDate(year: 2025, month: 6, day: 10, hour: 11),
            end: makeDate(year: 2025, month: 6, day: 10, hour: 12))

        _ = try await service.archiveActivity(id: archived.id!)

        let excluded = try await service.externalIdSummary(
            from: range.from, to: range.to, includeArchived: false
        )

        #expect(excluded.count == 1)
        #expect(excluded[0].externalId == "PROJ-500")
    }

    @Test func archivedActivityIncludedWhenRequested() async throws {
        let service = try makeService()
        let active = try await service.createActivity(CreateActivityInput(
            title: "Active", externalId: "PROJ-500"
        ))
        let archived = try await service.createActivity(CreateActivityInput(
            title: "Archived", externalId: "PROJ-501"
        ))

        let range = dayRange(year: 2025, month: 6, day: 10)
        try await addSession(service: service, activityId: active.id!,
            start: makeDate(year: 2025, month: 6, day: 10, hour: 9),
            end: makeDate(year: 2025, month: 6, day: 10, hour: 10))
        try await addSession(service: service, activityId: archived.id!,
            start: makeDate(year: 2025, month: 6, day: 10, hour: 11),
            end: makeDate(year: 2025, month: 6, day: 10, hour: 12))

        _ = try await service.archiveActivity(id: archived.id!)

        let included = try await service.externalIdSummary(
            from: range.from, to: range.to, includeArchived: true
        )

        #expect(included.count == 2)
        let ids = Set(included.map(\.externalId))
        #expect(ids == ["PROJ-500", "PROJ-501"])
    }

    // MARK: - Source URL Resolution

    @Test func sourceURLFromMostRecentSession() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(
            title: "Linked Work", externalId: "PROJ-600",
            link: "https://example.com/activity-link"
        ))

        let range = dayRange(year: 2025, month: 6, day: 10)

        // Earlier session (no session-level link; ticketId is null, so sourceURL
        // subquery falls to activity link for this session)
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 6, day: 10, hour: 9),
            end: makeDate(year: 2025, month: 6, day: 10, hour: 10))

        // Later session (also no session-level link)
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 6, day: 10, hour: 14),
            end: makeDate(year: 2025, month: 6, day: 10, hour: 15))

        let results = try await service.externalIdSummary(
            from: range.from, to: range.to, includeArchived: false
        )

        #expect(results.count == 1)
        // Both sessions lack a ticketId, so the subquery uses the activity link
        #expect(results[0].sourceURL == "https://example.com/activity-link")
    }

    @Test func sourceURLPrefersSessionLinkWhenTicketIdIsSet() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(
            title: "Ticket Work", externalId: "PROJ-700",
            link: "https://example.com/old-link"
        ))

        let range = dayRange(year: 2025, month: 6, day: 10)

        // Earlier session with no link (falls back to activity externalId)
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 6, day: 10, hour: 9),
            end: makeDate(year: 2025, month: 6, day: 10, hour: 10))

        // Later session with a ticket link — ticketId will be extracted,
        // so this session's link is preferred in the sourceURL subquery
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 6, day: 10, hour: 14),
            end: makeDate(year: 2025, month: 6, day: 10, hour: 15),
            link: "https://linear.app/team/issue/PROJ-700")

        // The session with the ticket link has ticketId="PROJ-700" which matches
        // the activity externalId="PROJ-700", so they're in the same group.
        // The sourceURL subquery picks the most recent session (the 2 PM one),
        // which has a ticketId, so it uses that session's link.
        let results = try await service.externalIdSummary(
            from: range.from, to: range.to, includeArchived: false
        )

        #expect(results.count == 1)
        #expect(results[0].sourceURL == "https://linear.app/team/issue/PROJ-700")
    }

    // MARK: - Ordering

    @Test func resultsOrderedByTotalSecondsDescending() async throws {
        let service = try makeService()
        let small = try await service.createActivity(CreateActivityInput(
            title: "Small", externalId: "SMALL-1"
        ))
        let large = try await service.createActivity(CreateActivityInput(
            title: "Large", externalId: "LARGE-1"
        ))

        let range = dayRange(year: 2025, month: 6, day: 10)

        // Small: 1h
        try await addSession(service: service, activityId: small.id!,
            start: makeDate(year: 2025, month: 6, day: 10, hour: 9),
            end: makeDate(year: 2025, month: 6, day: 10, hour: 10))

        // Large: 3h
        try await addSession(service: service, activityId: large.id!,
            start: makeDate(year: 2025, month: 6, day: 10, hour: 10),
            end: makeDate(year: 2025, month: 6, day: 10, hour: 13))

        let results = try await service.externalIdSummary(
            from: range.from, to: range.to, includeArchived: false
        )

        #expect(results.count == 2)
        #expect(results[0].externalId == "LARGE-1")
        #expect(results[1].externalId == "SMALL-1")
    }

    // MARK: - Empty Results

    @Test func emptyDateRangeReturnsNoResults() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(
            title: "Work", externalId: "PROJ-800"
        ))

        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 6, day: 10, hour: 9),
            end: makeDate(year: 2025, month: 6, day: 10, hour: 10))

        // Query a different day
        let range = dayRange(year: 2025, month: 6, day: 15)
        let results = try await service.externalIdSummary(
            from: range.from, to: range.to, includeArchived: false
        )

        #expect(results.isEmpty)
    }

    // MARK: - Multi-Day Range

    @Test func multiDayRangeAggregatesCorrectly() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(
            title: "Sprint Work", externalId: "SPRINT-1"
        ))

        // Sessions across three days
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 6, day: 10, hour: 9),
            end: makeDate(year: 2025, month: 6, day: 10, hour: 11)) // 2h
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 6, day: 11, hour: 9),
            end: makeDate(year: 2025, month: 6, day: 11, hour: 10)) // 1h
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 6, day: 12, hour: 14),
            end: makeDate(year: 2025, month: 6, day: 12, hour: 16)) // 2h

        // Query the full three-day range
        let from = makeDate(year: 2025, month: 6, day: 10, hour: 0)
        let to = makeDate(year: 2025, month: 6, day: 13, hour: 0)
        let results = try await service.externalIdSummary(
            from: from, to: to, includeArchived: false
        )

        #expect(results.count == 1)
        #expect(results[0].externalId == "SPRINT-1")
        #expect(results[0].totalSeconds == 18000) // 5h
        #expect(results[0].sessionCount == 3)
    }
}
