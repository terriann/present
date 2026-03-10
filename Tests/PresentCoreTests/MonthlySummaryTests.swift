import Testing
import Foundation
@testable import PresentCore

/// Tests for `PresentService.monthlySummary()`.
///
/// Uses past dates to avoid `createBackdatedSession` future-date rejection.
/// Primary test months:
///   - May 2025 (31 days, Thu start, all weeks covered with Monday weekStart)
///   - February 2024 (29 days, leap year, Thu start, all weeks covered with Monday weekStart)
@Suite("Monthly Summary Tests")
struct MonthlySummaryTests {

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

    @discardableResult
    private func addSession(
        service: PresentService,
        activityId: Int64,
        start: Date,
        end: Date
    ) async throws -> Session {
        try await service.createBackdatedSession(CreateBackdatedSessionInput(
            activityId: activityId, startedAt: start, endedAt: end
        ))
    }

    // MARK: - Basic

    @Test func emptyMonthReturnsZeros() async throws {
        let service = try makeService()
        let summary = try await service.monthlySummary(
            monthOf: makeDate(year: 2025, month: 8, day: 15),
            includeArchived: false, weekStartDay: 2
        )
        #expect(summary.totalSeconds == 0)
        #expect(summary.sessionCount == 0)
        #expect(summary.activities.isEmpty)
        #expect(summary.dailyBreakdown.allSatisfy { $0.totalSeconds == 0 })
    }

    // MARK: - Month Boundary Filtering

    /// Verifies that sessions in overlapping weeks before the month are excluded
    /// from totals, session counts, activity list, and daily breakdown.
    @Test func weekOverlappingStartOfMonthExcludesPreviousMonthData() async throws {
        let service = try makeService()
        let prevOnly = try await service.createActivity(CreateActivityInput(title: "Apr Only"))
        let currentOnly = try await service.createActivity(CreateActivityInput(title: "May Only"))
        let both = try await service.createActivity(CreateActivityInput(title: "Both"))

        // April 29 (Tue): 1h — in May's first week (Mon start), but excluded from May
        try await addSession(service: service, activityId: prevOnly.id!,
            start: makeDate(year: 2025, month: 4, day: 29, hour: 10),
            end: makeDate(year: 2025, month: 4, day: 29, hour: 11))

        // April 30: 3h in "Both" — excluded from May totals
        try await addSession(service: service, activityId: both.id!,
            start: makeDate(year: 2025, month: 4, day: 30, hour: 10),
            end: makeDate(year: 2025, month: 4, day: 30, hour: 13))

        // May 1 (Thu): 2h in "May Only"
        try await addSession(service: service, activityId: currentOnly.id!,
            start: makeDate(year: 2025, month: 5, day: 1, hour: 14),
            end: makeDate(year: 2025, month: 5, day: 1, hour: 16))

        // May 2: 1h in "Both" — included
        try await addSession(service: service, activityId: both.id!,
            start: makeDate(year: 2025, month: 5, day: 2, hour: 10),
            end: makeDate(year: 2025, month: 5, day: 2, hour: 11))

        let summary = try await service.monthlySummary(
            monthOf: makeDate(year: 2025, month: 5, day: 1),
            includeArchived: false, weekStartDay: 2
        )

        // Totals: May 1 (2h) + May 2 (1h) = 3h
        #expect(summary.totalSeconds == 10800)
        #expect(summary.sessionCount == 2)

        // Activities: "Apr Only" excluded, "Both" only has May portion
        let titles = Set(summary.activities.map(\.activity.title))
        #expect(!titles.contains("Apr Only"))
        #expect(titles.contains("May Only"))
        #expect(titles.contains("Both"))

        let bothSummary = summary.activities.first { $0.activity.title == "Both" }
        #expect(bothSummary?.totalSeconds == 3600) // 1h, not 3h+1h

        // Daily breakdown: all entries are in May
        let cal = Calendar.current
        #expect(summary.dailyBreakdown.allSatisfy { cal.component(.month, from: $0.date) == 5 })
    }

    /// Verifies that sessions in overlapping weeks after the month are excluded.
    @Test func weekOverlappingEndOfMonthExcludesNextMonthData() async throws {
        let service = try makeService()
        let mayActivity = try await service.createActivity(CreateActivityInput(title: "May Work"))
        let junActivity = try await service.createActivity(CreateActivityInput(title: "Jun Work"))

        // May 30 (Fri): 2h
        try await addSession(service: service, activityId: mayActivity.id!,
            start: makeDate(year: 2025, month: 5, day: 30, hour: 9),
            end: makeDate(year: 2025, month: 5, day: 30, hour: 11))

        // June 1 (Sun): 1h — same week, but excluded from May
        try await addSession(service: service, activityId: junActivity.id!,
            start: makeDate(year: 2025, month: 6, day: 1, hour: 9),
            end: makeDate(year: 2025, month: 6, day: 1, hour: 10))

        let summary = try await service.monthlySummary(
            monthOf: makeDate(year: 2025, month: 5, day: 15),
            includeArchived: false, weekStartDay: 2
        )

        #expect(summary.totalSeconds == 7200)
        #expect(summary.sessionCount == 1)
        #expect(summary.activities.count == 1)
        #expect(summary.activities[0].activity.title == "May Work")
    }

    // MARK: - Cross-Midnight at Month Boundary

    @Test func crossMidnightSessionAtMonthBoundarySplitsCorrectly() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Late Night"))

        // April 30 11 PM → May 1 2 AM (3h: 1h April, 2h May)
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 4, day: 30, hour: 23),
            end: makeDate(year: 2025, month: 5, day: 1, hour: 2))

        let maySummary = try await service.monthlySummary(
            monthOf: makeDate(year: 2025, month: 5, day: 1),
            includeArchived: false, weekStartDay: 2
        )
        #expect(maySummary.totalSeconds == 7200) // 2h in May

        let aprSummary = try await service.monthlySummary(
            monthOf: makeDate(year: 2025, month: 4, day: 15),
            includeArchived: false, weekStartDay: 2
        )
        #expect(aprSummary.totalSeconds == 3600) // 1h in April
    }

    // MARK: - Week Start Day

    /// Both Sunday and Monday week starts should yield the same month-only totals.
    @Test func weekStartDayDoesNotAffectMonthBoundaryFiltering() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Work"))

        // April 30 (Wed): 1h — would be in May's first week with some week starts
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 4, day: 30, hour: 10),
            end: makeDate(year: 2025, month: 4, day: 30, hour: 11))

        // May 1 (Thu): 2h
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 5, day: 1, hour: 10),
            end: makeDate(year: 2025, month: 5, day: 1, hour: 12))

        let sundayStart = try await service.monthlySummary(
            monthOf: makeDate(year: 2025, month: 5, day: 1),
            includeArchived: false, weekStartDay: 1
        )
        let mondayStart = try await service.monthlySummary(
            monthOf: makeDate(year: 2025, month: 5, day: 1),
            includeArchived: false, weekStartDay: 2
        )

        // Both should show only May data: 2h
        #expect(sundayStart.totalSeconds == 7200)
        #expect(mondayStart.totalSeconds == 7200)
        #expect(sundayStart.sessionCount == 1)
        #expect(mondayStart.sessionCount == 1)
    }

    // MARK: - Aggregation Consistency

    /// Monthly total must equal sum of daily breakdowns and sum of activity totals.
    @Test func totalMatchesSumOfDailyAndActivityBreakdowns() async throws {
        let service = try makeService()
        let a1 = try await service.createActivity(CreateActivityInput(title: "Coding"))
        let a2 = try await service.createActivity(CreateActivityInput(title: "Meetings"))

        try await addSession(service: service, activityId: a1.id!,
            start: makeDate(year: 2025, month: 5, day: 2, hour: 9),
            end: makeDate(year: 2025, month: 5, day: 2, hour: 12))
        try await addSession(service: service, activityId: a2.id!,
            start: makeDate(year: 2025, month: 5, day: 2, hour: 14),
            end: makeDate(year: 2025, month: 5, day: 2, hour: 15))
        try await addSession(service: service, activityId: a1.id!,
            start: makeDate(year: 2025, month: 5, day: 15, hour: 10),
            end: makeDate(year: 2025, month: 5, day: 15, hour: 14))
        try await addSession(service: service, activityId: a2.id!,
            start: makeDate(year: 2025, month: 5, day: 28, hour: 8),
            end: makeDate(year: 2025, month: 5, day: 28, hour: 10))

        let summary = try await service.monthlySummary(
            monthOf: makeDate(year: 2025, month: 5, day: 1),
            includeArchived: false, weekStartDay: 2
        )

        let dailyTotal = summary.dailyBreakdown.reduce(0) { $0 + $1.totalSeconds }
        let activityTotal = summary.activities.reduce(0) { $0 + $1.totalSeconds }

        #expect(summary.totalSeconds == dailyTotal)
        #expect(summary.totalSeconds == activityTotal)
        #expect(summary.totalSeconds == 36000) // 3h + 1h + 4h + 2h = 10h
    }

    // MARK: - Rounding

    @Test func roundToMinuteFloorsSessions() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Work"))

        // Session 1: 1h 30m exactly (5400s)
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 5, day: 10, hour: 9),
            end: makeDate(year: 2025, month: 5, day: 10, hour: 10, minute: 30))

        // Session 2: 45m 30s → floors to 45m (2700s)
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 5, day: 10, hour: 14),
            end: makeDate(year: 2025, month: 5, day: 10, hour: 14, minute: 45, second: 30))

        let rounded = try await service.monthlySummary(
            monthOf: makeDate(year: 2025, month: 5, day: 1),
            includeArchived: false, weekStartDay: 2, roundToMinute: true
        )
        let unrounded = try await service.monthlySummary(
            monthOf: makeDate(year: 2025, month: 5, day: 1),
            includeArchived: false, weekStartDay: 2, roundToMinute: false
        )

        // Rounded: 5400 + 2700 = 8100s. Unrounded: 5400 + 2730 = 8130s.
        #expect(rounded.totalSeconds == 8100)
        #expect(unrounded.totalSeconds == 8130)

        // Rounded total must equal sum of rounded dailies
        let dailyTotal = rounded.dailyBreakdown.reduce(0) { $0 + $1.totalSeconds }
        #expect(rounded.totalSeconds == dailyTotal)
    }

    // MARK: - February Edge Cases

    @Test func februaryLeapYearIncludesFeb29() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Work"))

        // Feb 29 2024 (leap year): 2h
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2024, month: 2, day: 29, hour: 10),
            end: makeDate(year: 2024, month: 2, day: 29, hour: 12))

        // March 1 2024: excluded from Feb
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2024, month: 3, day: 1, hour: 10),
            end: makeDate(year: 2024, month: 3, day: 1, hour: 11))

        let summary = try await service.monthlySummary(
            monthOf: makeDate(year: 2024, month: 2, day: 15),
            includeArchived: false, weekStartDay: 2
        )

        #expect(summary.totalSeconds == 7200)
        #expect(summary.sessionCount == 1)

        let cal = Calendar.current
        let hasFeb29 = summary.dailyBreakdown.contains {
            cal.component(.day, from: $0.date) == 29 && $0.sessionCount > 0
        }
        #expect(hasFeb29)
    }

    @Test func februaryNonLeapExcludesJanuaryData() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Work"))

        // Jan 31 2025: excluded from Feb
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 1, day: 31, hour: 10),
            end: makeDate(year: 2025, month: 1, day: 31, hour: 11))

        // Feb 10 2025 (Mon): 2h
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 2, day: 10, hour: 10),
            end: makeDate(year: 2025, month: 2, day: 10, hour: 12))

        let summary = try await service.monthlySummary(
            monthOf: makeDate(year: 2025, month: 2, day: 15),
            includeArchived: false, weekStartDay: 2
        )

        // Only Feb 10: 2h (Jan 31 excluded)
        #expect(summary.totalSeconds == 7200)
        #expect(summary.sessionCount == 1)
    }

    // MARK: - Last Week Skipping (#179)

    /// February 2026: Feb 1 is Sunday, Monday week start.
    /// The loop must visit the week of Feb 23 (Mon) which contains Feb 25.
    /// Before the fix, advancing by 7 from the mid-week `current` caused
    /// the loop to exit at Mar 1 without ever visiting the Feb 23 week.
    @Test func februaryWithSundayStartDoesNotSkipLastWeek() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Work"))

        // Feb 25 2026 (Wed) — in the last full week of Feb
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2026, month: 2, day: 25, hour: 10),
            end: makeDate(year: 2026, month: 2, day: 25, hour: 12))

        let summary = try await service.monthlySummary(
            monthOf: makeDate(year: 2026, month: 2, day: 1),
            includeArchived: false, weekStartDay: 2
        )

        #expect(summary.totalSeconds == 7200) // 2h
        #expect(summary.sessionCount == 1)

        let cal = Calendar.current
        let hasFeb25 = summary.dailyBreakdown.contains {
            cal.component(.day, from: $0.date) == 25 && $0.totalSeconds > 0
        }
        #expect(hasFeb25)
    }

    // MARK: - Hourly Breakdown Through Batch Path

    /// Verifies that hourly breakdown buckets are correctly populated when
    /// fetched through monthlySummary's batch path (not the per-day dailySummary).
    @Test func hourlyBreakdownPopulatedThroughBatchPath() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Focus"))

        // Session: May 10, 9:30 AM → 11:15 AM (spans hours 9, 10, 11)
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 5, day: 10, hour: 9, minute: 30),
            end: makeDate(year: 2025, month: 5, day: 10, hour: 11, minute: 15))

        let summary = try await service.monthlySummary(
            monthOf: makeDate(year: 2025, month: 5, day: 1),
            includeArchived: false, weekStartDay: 2
        )

        let cal = Calendar.current
        let may10 = summary.dailyBreakdown.first { cal.component(.day, from: $0.date) == 10 }
        let buckets = may10?.hourlyBreakdown.sorted { $0.hour < $1.hour } ?? []

        #expect(buckets.count == 3)
        #expect(buckets[0].hour == 9)
        #expect(buckets[0].totalSeconds == 1800) // 30m (9:30–10:00)
        #expect(buckets[1].hour == 10)
        #expect(buckets[1].totalSeconds == 3600) // 60m (10:00–11:00)
        #expect(buckets[2].hour == 11)
        #expect(buckets[2].totalSeconds == 900) // 15m (11:00–11:15)
    }

    /// Verifies hourly breakdown correctly splits a cross-midnight session
    /// across days when fetched through the monthly batch path.
    @Test func hourlyBreakdownCrossMidnightThroughBatchPath() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Late Night"))

        // Session: May 15 11:30 PM → May 16 1:30 AM
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 5, day: 15, hour: 23, minute: 30),
            end: makeDate(year: 2025, month: 5, day: 16, hour: 1, minute: 30))

        let summary = try await service.monthlySummary(
            monthOf: makeDate(year: 2025, month: 5, day: 1),
            includeArchived: false, weekStartDay: 2
        )

        let cal = Calendar.current
        let may15 = summary.dailyBreakdown.first { cal.component(.day, from: $0.date) == 15 }
        let may16 = summary.dailyBreakdown.first { cal.component(.day, from: $0.date) == 16 }

        let buckets15 = may15?.hourlyBreakdown ?? []
        #expect(buckets15.count == 1)
        #expect(buckets15[0].hour == 23)
        #expect(buckets15[0].totalSeconds == 1800) // 30m (11:30 PM–midnight)

        let buckets16 = (may16?.hourlyBreakdown ?? []).sorted { $0.hour < $1.hour }
        #expect(buckets16.count == 2)
        #expect(buckets16[0].hour == 0)
        #expect(buckets16[0].totalSeconds == 3600) // 60m (midnight–1 AM)
        #expect(buckets16[1].hour == 1)
        #expect(buckets16[1].totalSeconds == 1800) // 30m (1 AM–1:30 AM)
    }

    // MARK: - Cross-Midnight + Rounding Through Batch Path

    /// Verifies that per-session rounding works correctly when a cross-midnight
    /// session is split across days through the batch path. Each day's portion
    /// should be floored independently.
    @Test func crossMidnightWithRoundingThroughBatchPath() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Night Owl"))

        // Session: May 20 11:45:30 PM → May 21 1:15:45 AM
        // May 20 portion: 14m 30s → floors to 14m (840s)
        // May 21 portion: 1h 15m 45s → floors to 1h 15m (4500s)
        try await addSession(service: service, activityId: activity.id!,
            start: makeDate(year: 2025, month: 5, day: 20, hour: 23, minute: 45, second: 30),
            end: makeDate(year: 2025, month: 5, day: 21, hour: 1, minute: 15, second: 45))

        let rounded = try await service.monthlySummary(
            monthOf: makeDate(year: 2025, month: 5, day: 1),
            includeArchived: false, weekStartDay: 2, roundToMinute: true
        )
        let unrounded = try await service.monthlySummary(
            monthOf: makeDate(year: 2025, month: 5, day: 1),
            includeArchived: false, weekStartDay: 2, roundToMinute: false
        )

        let cal = Calendar.current
        let roundedMay20 = rounded.dailyBreakdown.first { cal.component(.day, from: $0.date) == 20 }
        let roundedMay21 = rounded.dailyBreakdown.first { cal.component(.day, from: $0.date) == 21 }

        // Rounded: each day's portion floored independently
        #expect(roundedMay20?.totalSeconds == 840)  // 14m
        #expect(roundedMay21?.totalSeconds == 4500)  // 1h 15m

        // Total should equal sum of floored day portions
        #expect(rounded.totalSeconds == 840 + 4500)

        // Unrounded: exact seconds
        let unroundedMay20 = unrounded.dailyBreakdown.first { cal.component(.day, from: $0.date) == 20 }
        let unroundedMay21 = unrounded.dailyBreakdown.first { cal.component(.day, from: $0.date) == 21 }
        #expect(unroundedMay20?.totalSeconds == 870)  // 14m 30s
        #expect(unroundedMay21?.totalSeconds == 4545)  // 1h 15m 45s
    }

    // MARK: - Archived Filtering

    @Test func archivedActivityExcludedWhenNotIncluded() async throws {
        let service = try makeService()
        let active = try await service.createActivity(CreateActivityInput(title: "Active Work"))
        let archived = try await service.createActivity(CreateActivityInput(title: "Old Work"))

        try await addSession(service: service, activityId: active.id!,
            start: makeDate(year: 2025, month: 5, day: 5, hour: 10),
            end: makeDate(year: 2025, month: 5, day: 5, hour: 12))
        try await addSession(service: service, activityId: archived.id!,
            start: makeDate(year: 2025, month: 5, day: 5, hour: 14),
            end: makeDate(year: 2025, month: 5, day: 5, hour: 16))

        _ = try await service.archiveActivity(id: archived.id!)

        let withArchived = try await service.monthlySummary(
            monthOf: makeDate(year: 2025, month: 5, day: 1),
            includeArchived: true, weekStartDay: 2
        )
        let withoutArchived = try await service.monthlySummary(
            monthOf: makeDate(year: 2025, month: 5, day: 1),
            includeArchived: false, weekStartDay: 2
        )

        #expect(withArchived.totalSeconds == 14400) // 4h
        #expect(withArchived.sessionCount == 2)
        #expect(withoutArchived.totalSeconds == 7200) // 2h
        #expect(withoutArchived.sessionCount == 1)
    }
}
