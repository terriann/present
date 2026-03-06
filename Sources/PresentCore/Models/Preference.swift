import Foundation
import GRDB

public struct Preference: Codable, Sendable, Equatable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

extension Preference: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "preference"

    public enum Columns {
        static let key = Column(CodingKeys.key)
        static let value = Column(CodingKeys.value)
    }
}

public enum PreferenceKey {
    public static let defaultRhythmMinutes = "defaultRhythmMinutes"
    public static let longBreakMinutes = "longBreakMinutes"
    public static let rhythmCycleLength = "rhythmCycleLength"
    public static let notificationSound = "notificationSound"
    public static let soundEffectsEnabled = "soundEffectsEnabled"
    public static let includeArchivedInReports = "includeArchivedInReports"
    public static let rhythmDurationOptions = "rhythmDurationOptions"
    public static let defaultTimeboundMinutes = "defaultTimeboundMinutes"
    public static let colorPalette = "colorPalette"
    public static let weekStartDay = "weekStartDay"
    public static let zoomLevel = "zoomLevel"
    public static let appearanceMode = "appearanceMode"
    public static let menuBarActivitySort = "menuBarActivitySort"

    public static let defaults: [(String, String)] = [
        (defaultRhythmMinutes, "25"),
        (longBreakMinutes, "15"),
        (rhythmCycleLength, "4"),
        (notificationSound, "1"),
        (soundEffectsEnabled, "1"),
        (includeArchivedInReports, "0"),
        (rhythmDurationOptions, "25:5,30:5,45:10"),
        (defaultTimeboundMinutes, "25"),
        (colorPalette, "basic"),
        (weekStartDay, "sunday"),
        (zoomLevel, "3"),
        (appearanceMode, "system"),
        (menuBarActivitySort, "recent"),
    ]

    /// Parse weekStartDay preference to Calendar.firstWeekday value.
    /// Returns 1 for Sunday (default), 2 for Monday.
    public static func parseWeekStartDay(_ value: String) -> Int {
        value.lowercased() == "monday" ? 2 : 1
    }

    /// Parse a serialized string of rhythm duration options into sorted, validated RhythmOption pairs.
    /// Supports legacy format ("25,30,45") and new format ("25:5,30:5,45:10").
    public static func parseRhythmOptions(_ value: String) -> [RhythmOption] {
        let isLegacy = !value.contains(":")

        let items = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var seen = Set<Int>()
        var result: [RhythmOption] = []

        for item in items {
            let option: RhythmOption?
            if isLegacy {
                // Legacy format: plain integers, default break to 5
                if let focus = Int(item), Constants.rhythmDurationRange.contains(focus) {
                    option = RhythmOption(focusMinutes: focus, breakMinutes: Constants.defaultShortBreakMinutes)
                } else {
                    option = nil
                }
            } else {
                // New format: "focus:break"
                let parts = item.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2,
                   let focus = Int(parts[0]), Constants.rhythmDurationRange.contains(focus),
                   let breakMins = Int(parts[1]), Constants.breakDurationRange.contains(breakMins) {
                    option = RhythmOption(focusMinutes: focus, breakMinutes: breakMins)
                } else {
                    option = nil
                }
            }

            if let opt = option, !seen.contains(opt.focusMinutes) {
                seen.insert(opt.focusMinutes)
                result.append(opt)
            }
        }

        result.sort { $0.focusMinutes < $1.focusMinutes }
        return Array(result.prefix(Constants.maxRhythmDurationOptions))
    }

    /// Serialize rhythm duration options to colon-pair format: "25:5,30:5,45:10".
    public static func serializeRhythmOptions(_ options: [RhythmOption]) -> String {
        options
            .sorted { $0.focusMinutes < $1.focusMinutes }
            .map { "\($0.focusMinutes):\($0.breakMinutes)" }
            .joined(separator: ",")
    }
}
