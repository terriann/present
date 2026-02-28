import Foundation

/// Shared input validation helpers for PresentService.
/// All user input validation lives here as the single source of truth.
public enum Validation {

    /// Sanitizes a string by trimming whitespace and rejecting control characters.
    /// Returns the trimmed string, or throws if it contains control characters or is empty.
    public static func sanitize(_ value: String, fieldName: String, maxLength: Int, allowEmpty: Bool = false) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if !allowEmpty && trimmed.isEmpty {
            throw PresentError.invalidInput("\(fieldName) cannot be empty.")
        }

        if containsControlCharacters(trimmed) {
            throw PresentError.invalidInput("\(fieldName) contains invalid characters.")
        }

        if trimmed.count > maxLength {
            throw PresentError.invalidInput("\(fieldName) exceeds maximum length of \(maxLength) characters.")
        }

        return trimmed
    }

    /// Validates an optional string field. Returns nil for nil/empty input, or the sanitized value.
    public static func sanitizeOptional(_ value: String?, fieldName: String, maxLength: Int) throws -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return try sanitize(value, fieldName: fieldName, maxLength: maxLength)
    }

    /// Validates a URL string has a reasonable format (http/https scheme + host).
    public static func validateLink(_ value: String) throws {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            throw PresentError.invalidInput("Link must be a valid URL with http or https scheme (e.g., https://example.com).")
        }
    }

    /// Validates an integer is within a given range.
    public static func validateRange(_ value: Int, range: ClosedRange<Int>, fieldName: String) throws {
        guard range.contains(value) else {
            throw PresentError.invalidInput("\(fieldName) must be between \(range.lowerBound) and \(range.upperBound).")
        }
    }

    /// Returns the list of known preference keys.
    public static let knownPreferenceKeys: Set<String> = Set(PreferenceKey.defaults.map(\.0))

    /// Validates a preference key is a known key. Throws if unknown.
    public static func validatePreferenceKey(_ key: String) throws {
        guard knownPreferenceKeys.contains(key) else {
            let known = knownPreferenceKeys.sorted().joined(separator: ", ")
            throw PresentError.invalidInput("Unknown preference key: \(key). Known keys: \(known)")
        }
    }

    /// Checks whether a string contains ASCII control characters (excluding tab, newline, carriage return).
    private static func containsControlCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            scalar.value < 32 && scalar.value != 9 && scalar.value != 10 && scalar.value != 13
        }
    }
}
