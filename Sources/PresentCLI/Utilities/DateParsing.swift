import ArgumentParser
import Foundation

/// Shared date parsing utilities for CLI commands.
/// Consolidates the various date format handling into a consistent set of parsers.
enum DateParsing {

    // MARK: - Date-Only (YYYY-MM-DD)

    /// Parse a date-only string (`YYYY-MM-DD`) or exit with a descriptive error.
    /// Used by `--after` and `--before` flags.
    static func parseDateOrFail(_ string: String, label: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        guard let date = formatter.date(from: string) else {
            print("Invalid date format for \(label): \(string). Use YYYY-MM-DD.")
            throw ExitCode.failure
        }
        return date
    }

    // MARK: - ISO8601 DateTime

    /// Parse an ISO8601 datetime string or exit with a descriptive error.
    /// Tries fractional seconds, standard ISO8601, then local format without timezone.
    /// Used by `--started-at` and `--ended-at` flags.
    static func parseDateTimeOrFail(_ string: String, label: String) throws -> Date {
        if let date = parseDateTime(string) { return date }
        print("Invalid \(label): \(string). Use ISO8601 format (e.g., 2026-01-15T09:30:00).")
        throw ExitCode.failure
    }

    /// Parse an ISO8601 datetime string, returning nil on failure.
    /// Tries: fractional seconds ISO8601, standard ISO8601, local datetime without timezone.
    static func parseDateTime(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]

        return fractional.date(from: string)
            ?? standard.date(from: string)
            ?? parseLocalISO(string)
    }

    // MARK: - Private

    /// Parse a local ISO8601 datetime without timezone (e.g., "2026-01-15T09:30:00").
    private static func parseLocalISO(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = .current
        return formatter.date(from: string)
    }
}
