import Testing
import Foundation
@testable import PresentCore

@Suite("TimeFormatting Tests")
struct TimeFormattingTests {

    // MARK: - formatTime(_:referenceDate:)

    @Test func sameDayReturnsPlainTime() {
        // Two dates on the same calendar day should produce just the time string
        let calendar = Calendar.current
        let reference = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 22, hour: 10, minute: 0)
        )!
        let date = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 22, hour: 14, minute: 30)
        )!

        let result = TimeFormatting.formatTime(date, referenceDate: reference)
        let plainTime = TimeFormatting.formatTime(date)

        #expect(result == plainTime)
        #expect(!result.contains("("))
        #expect(!result.contains(")"))
    }

    @Test func differentDayAppendsDayName() {
        // Date on a different calendar day should append "(DayName)"
        let calendar = Calendar.current
        let reference = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 22, hour: 10, minute: 0)
        )!
        // Feb 21, 2026 is a Saturday
        let date = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 21, hour: 9, minute: 15)
        )!

        let result = TimeFormatting.formatTime(date, referenceDate: reference)
        let plainTime = TimeFormatting.formatTime(date)

        // Build expected day name using the same formatter the implementation uses
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"
        let expectedDayName = dayFormatter.string(from: date)

        #expect(result == "\(plainTime) (\(expectedDayName))")
        #expect(result.contains("("))
        #expect(result.contains(")"))
    }

    @Test func crossMidnightJustAfterMidnight() {
        // Reference at 11:58 PM, date at 12:02 AM the next day
        let calendar = Calendar.current
        let reference = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 22, hour: 23, minute: 58)
        )!
        let date = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 23, hour: 0, minute: 2)
        )!

        let result = TimeFormatting.formatTime(date, referenceDate: reference)
        let plainTime = TimeFormatting.formatTime(date)

        // Different calendar days, so day name should be appended
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"
        let expectedDayName = dayFormatter.string(from: date)

        #expect(result == "\(plainTime) (\(expectedDayName))")
    }

    @Test func crossMidnightJustBeforeMidnight() {
        // Reference at 12:02 AM, date at 11:58 PM the previous day
        let calendar = Calendar.current
        let reference = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 23, hour: 0, minute: 2)
        )!
        let date = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 22, hour: 23, minute: 58)
        )!

        let result = TimeFormatting.formatTime(date, referenceDate: reference)
        let plainTime = TimeFormatting.formatTime(date)

        // Different calendar days, so day name should be appended
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"
        let expectedDayName = dayFormatter.string(from: date)

        #expect(result == "\(plainTime) (\(expectedDayName))")
    }

    @Test func sameDateIdenticalTimestamps() {
        // Identical date and reference should return plain time
        let calendar = Calendar.current
        let date = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 22, hour: 15, minute: 45)
        )!

        let result = TimeFormatting.formatTime(date, referenceDate: date)
        let plainTime = TimeFormatting.formatTime(date)

        #expect(result == plainTime)
    }

    @Test func differentDayResultContainsFullWeekdayName() {
        // Verify the parenthetical contains a full weekday name, not abbreviated
        let calendar = Calendar.current
        let reference = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 22, hour: 10, minute: 0)
        )!
        // Feb 20, 2026 is a Friday
        let date = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 20, hour: 14, minute: 0)
        )!

        let result = TimeFormatting.formatTime(date, referenceDate: reference)

        // Full weekday names are at least 6 characters (Monday, Friday, etc.)
        // Abbreviated names are 3 characters (Mon, Fri, etc.)
        // Extract the parenthetical content
        let openParen = result.firstIndex(of: "(")!
        let closeParen = result.firstIndex(of: ")")!
        let dayName = String(result[result.index(after: openParen)..<closeParen])

        #expect(dayName.count >= 6, "Expected full weekday name, got '\(dayName)'")
    }
}
