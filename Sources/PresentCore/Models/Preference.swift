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
    public static let externalIdBaseUrl = "externalIdBaseUrl"
    public static let defaultRhythmMinutes = "defaultRhythmMinutes"
    public static let shortBreakMinutes = "shortBreakMinutes"
    public static let longBreakMinutes = "longBreakMinutes"
    public static let rhythmCycleLength = "rhythmCycleLength"
    public static let notificationSound = "notificationSound"
    public static let includeArchivedInReports = "includeArchivedInReports"

    public static let defaults: [(String, String)] = [
        (externalIdBaseUrl, ""),
        (defaultRhythmMinutes, "25"),
        (shortBreakMinutes, "5"),
        (longBreakMinutes, "15"),
        (rhythmCycleLength, "4"),
        (notificationSound, "1"),
        (includeArchivedInReports, "0"),
    ]
}
