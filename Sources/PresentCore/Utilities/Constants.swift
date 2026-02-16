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
    public static let defaultTimeboundMinutes = 25
    public static let timeboundDurationRange = 5...120
    public static let rhythmDurationRange = 1...120
    public static let breakDurationRange = 1...60

    // MARK: - Validation Limits

    public static let maxTitleLength = 200
    public static let maxTagNameLength = 100
    public static let maxExternalIdLength = 255
    public static let maxLinkLength = 2000
    public static let maxNotesLength = 50_000
    public static let maxSearchQueryLength = 200
    public static let minSearchQueryLength = 1
    public static let sessionMinutesRange = 1...480

    // MARK: - Menu Bar Timer Linger

    public static let completedTimerLingerSeconds = 120
    public static let completedTimerFlashSeconds = 6
    public static let completedTimerFadeSeconds = 10
    public static let menuBarTimerPausedOpacity = 0.8
    public static let menuBarTimerLingerOpacity = 0.6
}
