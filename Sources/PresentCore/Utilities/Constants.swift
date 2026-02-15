import Foundation

public enum Constants {
    public static let appName = "Present"
    public static let bundleIdentifier = "com.present.app"
    public static let maxActiveActivities = 50
    public static let archiveDeleteThresholdSeconds = 600 // 10 minutes
    public static let defaultRhythmMinutes = 25
    public static let longBreakMinutes = 15
    public static let defaultShortBreakMinutes = 5
    public static let rhythmCycleLength = 4
    public static let recentActivitiesLimit = 6
    public static let defaultRhythmDurationOptions: [RhythmOption] = [
        RhythmOption(focusMinutes: 25, breakMinutes: 5),
        RhythmOption(focusMinutes: 30, breakMinutes: 5),
        RhythmOption(focusMinutes: 45, breakMinutes: 10),
    ]
    public static let maxRhythmDurationOptions = 5
    public static let rhythmDurationRange = 1...120
    public static let breakDurationRange = 1...60
}
