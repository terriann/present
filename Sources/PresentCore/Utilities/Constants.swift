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
    public static let maxSessionNoteLength = 10_000
    public static let maxSessionLinkLength = 2000
    public static let maxSearchQueryLength = 200
    public static let minSearchQueryLength = 1
    public static let sessionMinutesRange = 1...480

    // MARK: - Session Cancel Window

    public static let cancelWindowSeconds = 10

    // MARK: - Menu Bar Timer Linger

    public static let completedTimerLingerSeconds = 120
    public static let completedTimerFadeSeconds = 10

    // MARK: - Spacing

    /// Main content areas (ScrollView roots: Dashboard, ActivityDetail, Reports, sheets)
    public static let spacingPage: CGFloat = 20
    /// Toolbars and navigation bars
    public static let spacingToolbar: CGFloat = 16
    /// Card/GroupBox internals, menu bar sections, chart cards
    public static let spacingCard: CGFloat = 12
    /// Compact/dense UI (menu bar items, pills, badges, inline spacing)
    public static let spacingCompact: CGFloat = 8
    /// Tight inner padding (GroupBox content wrappers)
    public static let spacingTight: CGFloat = 4

    // MARK: - Corner Radius

    /// Small corner radius for inline highlights, pills, and legend row backgrounds
    public static let cornerRadiusSmall: CGFloat = 4

    // MARK: - Activity List

    /// Minimum row height for activity list items, matching the two-line variant (title + subtitle).
    public static let activityRowMinHeight: CGFloat = 44

    // MARK: - System Activities

    public static let breakActivityTitle = "Break"

    // MARK: - Active Session Pulse

    /// Peak opacity for the active session pulse animation.
    public static let activePulseHigh: Double = 0.75
    /// Trough opacity for the active session pulse animation.
    public static let activePulseLow: Double = 0.3
    /// Duration (seconds) for each fade direction (high→low or low→high).
    public static let activePulseDuration: Double = 3.0
    /// Pause (seconds) at the low point before fading back up.
    public static let activePulseDelay: Double = 1.0
    /// Milliseconds between pulse animation state updates (~6.7fps).
    public static let activePulseInterval: Int = 150

    // MARK: - Version

    public static let appVersion = "0.2.0-dev"

}

// MARK: - SwiftUI Constants

#if canImport(SwiftUI)
import SwiftUI

extension Constants {
    /// Subtle background applied to alternating rows in session lists.
    /// Defined once to prevent drift across call sites.
    public static let alternatingRowBackground = Color(
        light: Color.black.opacity(0.06),
        dark: Color.white.opacity(0.06)
    )

    /// Subtle shading behind weekend columns in bar charts.
    /// Currently matches `alternatingRowBackground` but can be tuned independently.
    public static let weekendBackground = alternatingRowBackground
}
#endif
