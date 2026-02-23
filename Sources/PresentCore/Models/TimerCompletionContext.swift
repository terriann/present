import Foundation

public struct TimerCompletionContext: Sendable, Equatable {
    public enum CompletionType: Sendable, Equatable {
        case timeboundExpiry
        case rhythmFocusExpiry(breakMinutes: Int, isLongBreak: Bool)
        case rhythmBreakExpiry(previousActivityId: Int64, previousActivityTitle: String,
                               previousTimerMinutes: Int, previousBreakMinutes: Int)
        case timeboundBreakExpiry(recentActivityId: Int64?, recentActivityTitle: String?,
                                  recentTimerMinutes: Int?, recentSessionType: SessionType?)

        public var isBreakExpiry: Bool {
            switch self {
            case .rhythmBreakExpiry, .timeboundBreakExpiry: return true
            default: return false
            }
        }

        public var isTimeboundBreakExpiry: Bool {
            if case .timeboundBreakExpiry = self { return true }
            return false
        }

        public var isFocusExpiry: Bool {
            if case .rhythmFocusExpiry = self { return true }
            return false
        }
    }

    public let completionType: CompletionType
    public let activityId: Int64
    public let activityTitle: String
    public let durationFormatted: String
    public let timerMinutes: Int

    public init(
        completionType: CompletionType,
        activityId: Int64,
        activityTitle: String,
        durationFormatted: String,
        timerMinutes: Int
    ) {
        self.completionType = completionType
        self.activityId = activityId
        self.activityTitle = activityTitle
        self.durationFormatted = durationFormatted
        self.timerMinutes = timerMinutes
    }
}
