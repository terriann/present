import Testing
import Foundation
import GRDB
@testable import PresentCore

/// Tests for timezone edge cases: DST transitions, cross-midnight in different timezones,
/// leap year dates, and very long sessions.
///
/// **TimeFormatting tests** use injected `Calendar` objects with pinned timezones, making them
/// fully hermetic (they produce the same results on any machine).
///
/// **Service-level tests** use `Calendar.current` for date construction (matching production
/// behavior). Duration assertions via `timeIntervalSince` are always timezone-independent.
/// Daily summary assertions use the machine's local timezone for day boundaries, which means
/// DST-specific daily splits are only exercised when run in a DST-observing timezone.
@Suite("Timezone & DST Edge Case Tests")
struct TimezoneEdgeCaseTests {

    // MARK: - Helpers

    private func makeService() throws -> PresentService {
        let dbManager = try DatabaseManager(inMemory: true)
        return PresentService(databasePool: dbManager.writer)
    }

    /// Build a `Calendar` pinned to a specific timezone.
    private func makeCalendar(timeZoneId: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneId)!
        return calendar
    }

    /// Build a `Date` in a specific timezone's wall-clock interpretation.
    private func makeDate(
        year: Int, month: Int, day: Int,
        hour: Int = 0, minute: Int = 0, second: Int = 0,
        calendar: Calendar
    ) -> Date {
        let components = DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        )
        return calendar.date(from: components)!
    }

    /// Build a `Date` using the machine's current calendar (matches existing test patterns).
    private func makeLocalDate(
        year: Int, month: Int, day: Int,
        hour: Int = 0, minute: Int = 0
    ) -> Date {
        let components = DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: 0
        )
        return Calendar.current.date(from: components)!
    }

    // MARK: - DST Spring Forward (TimeFormatting)
    // America/New_York: March 10, 2024 — clocks jump from 2:00 AM to 3:00 AM

    @Test func formatTimeSpringForwardSameDayDetection() {
        // Two times on the same DST transition day should be recognized as same-day
        let ny = makeCalendar(timeZoneId: "America/New_York")
        let preTransition = makeDate(year: 2024, month: 3, day: 10, hour: 1, minute: 30, calendar: ny)
        let postTransition = makeDate(year: 2024, month: 3, day: 10, hour: 3, minute: 30, calendar: ny)

        let result = TimeFormatting.formatTime(postTransition, referenceDate: preTransition, calendar: ny)

        // Same calendar day in NY — no day name appended
        #expect(!result.contains("("), "Expected same-day detection across spring-forward boundary")
    }

    @Test func formatTimeSpringForwardCrossMidnight() {
        // 11:30 PM March 9 → 3:30 AM March 10 (crosses midnight AND DST transition)
        let ny = makeCalendar(timeZoneId: "America/New_York")
        let beforeMidnight = makeDate(year: 2024, month: 3, day: 9, hour: 23, minute: 30, calendar: ny)
        let afterTransition = makeDate(year: 2024, month: 3, day: 10, hour: 3, minute: 30, calendar: ny)

        let result = TimeFormatting.formatTime(afterTransition, referenceDate: beforeMidnight, calendar: ny)

        // Different calendar days — day name should be appended
        #expect(result.contains("("), "Expected day name for cross-midnight + DST transition")
    }

    @Test func springForwardDurationIsCorrect() {
        // 1:00 AM → 4:00 AM on spring-forward day: wall clock shows 3h, but only 2h elapsed
        // (the 2:00–3:00 AM hour is skipped)
        let ny = makeCalendar(timeZoneId: "America/New_York")
        let start = makeDate(year: 2024, month: 3, day: 10, hour: 1, calendar: ny)
        let end = makeDate(year: 2024, month: 3, day: 10, hour: 4, calendar: ny)

        let elapsed = Int(end.timeIntervalSince(start))

        // 2 hours = 7200 seconds (not 3 hours)
        #expect(elapsed == 7200, "Spring forward: 1 AM → 4 AM should be 2h, not 3h")
    }

    @Test func springForwardBackdatedSessionDuration() async throws {
        // Verify the service stores the correct duration across a spring-forward transition
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Spring Forward"))

        let ny = makeCalendar(timeZoneId: "America/New_York")
        let start = makeDate(year: 2024, month: 3, day: 10, hour: 1, calendar: ny)
        let end = makeDate(year: 2024, month: 3, day: 10, hour: 4, calendar: ny)

        let session = try await service.createBackdatedSession(
            CreateBackdatedSessionInput(activityId: activity.id!, startedAt: start, endedAt: end)
        )

        // Service should store 7200s (2h), not 10800s (3h)
        #expect(session.durationSeconds == 7200)
    }

    // MARK: - DST Fall Back (TimeFormatting)
    // America/New_York: November 3, 2024 — clocks fall from 2:00 AM back to 1:00 AM

    @Test func formatTimeFallBackSameDayDetection() {
        // Two times on the same fall-back day should be recognized as same-day
        let ny = makeCalendar(timeZoneId: "America/New_York")
        let earlyMorning = makeDate(year: 2024, month: 11, day: 3, hour: 0, minute: 30, calendar: ny)
        let afterFallBack = makeDate(year: 2024, month: 11, day: 3, hour: 3, minute: 30, calendar: ny)

        let result = TimeFormatting.formatTime(afterFallBack, referenceDate: earlyMorning, calendar: ny)

        // Same calendar day — no day name
        #expect(!result.contains("("), "Expected same-day detection across fall-back boundary")
    }

    @Test func fallBackDurationIsCorrect() {
        // Midnight → 3:00 AM on fall-back day: wall clock shows 3h, but 4h elapsed
        // (the 1:00–2:00 AM hour happens twice)
        let ny = makeCalendar(timeZoneId: "America/New_York")
        let start = makeDate(year: 2024, month: 11, day: 3, hour: 0, calendar: ny)
        let end = makeDate(year: 2024, month: 11, day: 3, hour: 3, calendar: ny)

        let elapsed = Int(end.timeIntervalSince(start))

        // 4 hours = 14400 seconds (not 3 hours)
        #expect(elapsed == 14400, "Fall back: midnight → 3 AM should be 4h, not 3h")
    }

    @Test func fallBackBackdatedSessionDuration() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Fall Back"))

        let ny = makeCalendar(timeZoneId: "America/New_York")
        let start = makeDate(year: 2024, month: 11, day: 3, hour: 0, calendar: ny)
        let end = makeDate(year: 2024, month: 11, day: 3, hour: 3, calendar: ny)

        let session = try await service.createBackdatedSession(
            CreateBackdatedSessionInput(activityId: activity.id!, startedAt: start, endedAt: end)
        )

        // Service should store 14400s (4h), not 10800s (3h)
        #expect(session.durationSeconds == 14400)
    }

    // MARK: - Cross-Midnight in Specific Timezones

    @Test func formatTimeCrossMidnightNewZealand() {
        // 11:30 PM → 0:30 AM in Pacific/Auckland — different calendar days
        let nz = makeCalendar(timeZoneId: "Pacific/Auckland")
        let late = makeDate(year: 2024, month: 6, day: 15, hour: 23, minute: 30, calendar: nz)
        let early = makeDate(year: 2024, month: 6, day: 16, hour: 0, minute: 30, calendar: nz)

        let result = TimeFormatting.formatTime(early, referenceDate: late, calendar: nz)

        #expect(result.contains("("), "Cross-midnight in NZ should append day name")
    }

    @Test func formatTimeSameDayDifferentTimezoneInterpretation() {
        // A UTC time that falls on different calendar days depending on timezone.
        // March 15, 2024 at 3:00 AM UTC = March 14 at 10:00 PM ET (different day!)
        let utcCal = makeCalendar(timeZoneId: "UTC")
        let nyCal = makeCalendar(timeZoneId: "America/New_York")

        let date = makeDate(year: 2024, month: 3, day: 15, hour: 3, calendar: utcCal)
        let reference = makeDate(year: 2024, month: 3, day: 15, hour: 10, calendar: utcCal)

        // In UTC: both are March 15 — same day
        let utcResult = TimeFormatting.formatTime(date, referenceDate: reference, calendar: utcCal)
        #expect(!utcResult.contains("("), "Same day in UTC")

        // In NY: date is March 14 10 PM, reference is March 15 6 AM — different days
        let nyResult = TimeFormatting.formatTime(date, referenceDate: reference, calendar: nyCal)
        #expect(nyResult.contains("("), "Different days in America/New_York")
    }

    @Test func crossMidnightSessionNewZealand() async throws {
        // Session spanning midnight in NZ timezone — duration should be correct
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "NZ Late Night"))

        let nz = makeCalendar(timeZoneId: "Pacific/Auckland")
        let start = makeDate(year: 2024, month: 6, day: 15, hour: 23, calendar: nz)
        let end = makeDate(year: 2024, month: 6, day: 16, hour: 1, calendar: nz)

        let session = try await service.createBackdatedSession(
            CreateBackdatedSessionInput(activityId: activity.id!, startedAt: start, endedAt: end)
        )

        // 2 hours regardless of timezone
        #expect(session.durationSeconds == 7200)
    }

    // MARK: - formatWeekRange with Timezones

    @Test func weekRangeCrossYearInNewZealand() {
        // Week spanning Dec 2024 → Jan 2025 in NZ
        let nz = makeCalendar(timeZoneId: "Pacific/Auckland")
        let start = makeDate(year: 2024, month: 12, day: 30, hour: 12, calendar: nz)
        let end = makeDate(year: 2025, month: 1, day: 5, hour: 12, calendar: nz)

        let result = TimeFormatting.formatWeekRange(start: start, end: end, calendar: nz)

        // Different years — both dates should include the year
        #expect(result.contains("2024"), "Start year should appear")
        #expect(result.contains("2025"), "End year should appear")
    }

    @Test func weekRangeSameYearInTokyo() {
        // Week within 2024, viewed from Asia/Tokyo
        let tokyo = makeCalendar(timeZoneId: "Asia/Tokyo")
        let start = makeDate(year: 2024, month: 6, day: 10, hour: 12, calendar: tokyo)
        let end = makeDate(year: 2024, month: 6, day: 16, hour: 12, calendar: tokyo)

        let result = TimeFormatting.formatWeekRange(start: start, end: end, calendar: tokyo)

        // Same year — only end date should have the year
        #expect(result.contains("June 10"))
        #expect(result.contains("June 16, 2024"))
    }

    // MARK: - Leap Year

    @Test func backdatedSessionOnLeapDay() async throws {
        // Session entirely on Feb 29, 2024 (valid leap year)
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Leap Day Work"))

        let start = makeLocalDate(year: 2024, month: 2, day: 29, hour: 9)
        let end = makeLocalDate(year: 2024, month: 2, day: 29, hour: 17)

        let session = try await service.createBackdatedSession(
            CreateBackdatedSessionInput(activityId: activity.id!, startedAt: start, endedAt: end)
        )

        #expect(session.durationSeconds == 28800) // 8 hours
        #expect(session.startedAt == start)
        #expect(session.endedAt == end)
    }

    @Test func dailySummaryLeapDay() async throws {
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Leap Day"))

        let start = makeLocalDate(year: 2024, month: 2, day: 29, hour: 10)
        let end = makeLocalDate(year: 2024, month: 2, day: 29, hour: 14)

        _ = try await service.createBackdatedSession(
            CreateBackdatedSessionInput(activityId: activity.id!, startedAt: start, endedAt: end)
        )

        let queryDate = makeLocalDate(year: 2024, month: 2, day: 29, hour: 12)
        let summary = try await service.dailySummary(date: queryDate, includeArchived: false)

        #expect(summary.sessionCount == 1)
        #expect(summary.totalSeconds == 14400) // 4 hours
        #expect(summary.activities.count == 1)
        #expect(summary.activities[0].activity.title == "Leap Day")
    }

    @Test func sessionSpanningLeapDay() async throws {
        // Session from Feb 28 evening to Mar 1 morning (crosses Feb 29)
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Leap Span"))

        let start = makeLocalDate(year: 2024, month: 2, day: 28, hour: 22)
        let end = makeLocalDate(year: 2024, month: 3, day: 1, hour: 2)

        let session = try await service.createBackdatedSession(
            CreateBackdatedSessionInput(activityId: activity.id!, startedAt: start, endedAt: end)
        )

        // Feb 28 10 PM → Mar 1 2 AM = 28 hours
        #expect(session.durationSeconds == 28 * 3600)

        // Feb 29 daily summary should attribute 24h (full day)
        let feb29 = makeLocalDate(year: 2024, month: 2, day: 29, hour: 12)
        let summary = try await service.dailySummary(date: feb29, includeArchived: false)
        #expect(summary.totalSeconds == 86400) // 24 hours
    }

    // MARK: - Very Long Sessions

    @Test func sessionSpanningThreeDays() async throws {
        // 72-hour session: Jan 10 9 AM → Jan 13 9 AM
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Marathon"))

        let start = makeLocalDate(year: 2024, month: 1, day: 10, hour: 9)
        let end = makeLocalDate(year: 2024, month: 1, day: 13, hour: 9)

        let session = try await service.createBackdatedSession(
            CreateBackdatedSessionInput(activityId: activity.id!, startedAt: start, endedAt: end)
        )

        #expect(session.durationSeconds == 3 * 86400) // 72 hours

        // Middle day (Jan 11) should attribute exactly 24h
        let jan11 = makeLocalDate(year: 2024, month: 1, day: 11, hour: 12)
        let summary = try await service.dailySummary(date: jan11, includeArchived: false)
        #expect(summary.totalSeconds == 86400)
        #expect(summary.sessionCount == 1)

        // First day (Jan 10) should attribute 15h (9 AM to midnight)
        let jan10 = makeLocalDate(year: 2024, month: 1, day: 10, hour: 12)
        let jan10Summary = try await service.dailySummary(date: jan10, includeArchived: false)
        #expect(jan10Summary.totalSeconds == 15 * 3600)

        // Last day (Jan 13) should attribute 9h (midnight to 9 AM)
        let jan13 = makeLocalDate(year: 2024, month: 1, day: 13, hour: 12)
        let jan13Summary = try await service.dailySummary(date: jan13, includeArchived: false)
        #expect(jan13Summary.totalSeconds == 9 * 3600)
    }

    @Test func sessionSpanningWeekBoundary() async throws {
        // Session spanning Sunday → Monday (week boundary with Monday start)
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Week Span"))

        // Jan 14, 2024 is a Sunday; Jan 15 is a Monday
        let start = makeLocalDate(year: 2024, month: 1, day: 14, hour: 22) // Sun 10 PM
        let end = makeLocalDate(year: 2024, month: 1, day: 15, hour: 6)   // Mon 6 AM

        _ = try await service.createBackdatedSession(
            CreateBackdatedSessionInput(activityId: activity.id!, startedAt: start, endedAt: end)
        )

        // Weekly summary for the week containing Jan 14 (Sunday, weekStartDay=2 for Monday)
        // Jan 14 is the last day of week Jan 8–14
        let week1Date = makeLocalDate(year: 2024, month: 1, day: 12, hour: 12)
        let week1 = try await service.weeklySummary(weekOf: week1Date, includeArchived: false, weekStartDay: 2)

        // Weekly summary for week containing Jan 15 (Mon Jan 15–21)
        let week2Date = makeLocalDate(year: 2024, month: 1, day: 16, hour: 12)
        let week2 = try await service.weeklySummary(weekOf: week2Date, includeArchived: false, weekStartDay: 2)

        // Sunday (Jan 14): 2h (10 PM to midnight)
        #expect(week1.totalSeconds == 2 * 3600)
        // Monday (Jan 15): 6h (midnight to 6 AM)
        #expect(week2.totalSeconds == 6 * 3600)
    }

    @Test func veryLongSessionSevenDays() async throws {
        // 7-day session
        let service = try makeService()
        let activity = try await service.createActivity(CreateActivityInput(title: "Ultramarathon"))

        let start = makeLocalDate(year: 2024, month: 1, day: 1, hour: 0)
        let end = makeLocalDate(year: 2024, month: 1, day: 8, hour: 0)

        let session = try await service.createBackdatedSession(
            CreateBackdatedSessionInput(activityId: activity.id!, startedAt: start, endedAt: end)
        )

        #expect(session.durationSeconds == 7 * 86400) // 168 hours

        // Each full day should attribute 24h
        for day in 1...7 {
            let date = makeLocalDate(year: 2024, month: 1, day: day, hour: 12)
            let summary = try await service.dailySummary(date: date, includeArchived: false)
            #expect(
                summary.totalSeconds == 86400,
                "Day \(day) should have 24h, got \(summary.totalSeconds)s"
            )
        }

        // Day 8 should have 0h (session ends at midnight)
        let day8 = makeLocalDate(year: 2024, month: 1, day: 8, hour: 12)
        let day8Summary = try await service.dailySummary(date: day8, includeArchived: false)
        #expect(day8Summary.totalSeconds == 0)
    }
}
