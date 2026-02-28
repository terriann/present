import Testing
import Foundation
@testable import PresentCore

@Suite("Model Tests")
struct ModelTests {

    @Test func sessionTypeRawValues() {
        #expect(SessionType.work.rawValue == "work")
        #expect(SessionType.rhythm.rawValue == "rhythm")
        #expect(SessionType.timebound.rawValue == "timebound")
    }

    @Test func sessionStateRawValues() {
        #expect(SessionState.running.rawValue == "running")
        #expect(SessionState.paused.rawValue == "paused")
        #expect(SessionState.completed.rawValue == "completed")
        #expect(SessionState.cancelled.rawValue == "cancelled")
    }

    @Test func sessionTypeConfigs() {
        #expect(SessionTypeConfig.all.count == 3)
        for type in SessionType.allCases {
            let config = SessionTypeConfig.config(for: type)
            #expect(!config.displayName.isEmpty)
            #expect(!config.description.isEmpty)
        }
    }

    @Test func activityDefaults() {
        let activity = Activity(title: "Test")
        #expect(activity.id == nil)
        #expect(activity.title == "Test")
        #expect(activity.isArchived == false)
        #expect(activity.externalId == nil)
        #expect(activity.link == nil)
        #expect(activity.notes == nil)
    }

    @Test func sessionDefaults() {
        let session = Session(activityId: 1, sessionType: .work)
        #expect(session.id == nil)
        #expect(session.activityId == 1)
        #expect(session.sessionType == .work)
        #expect(session.state == .running)
        #expect(session.totalPausedSeconds == 0)
        #expect(session.endedAt == nil)
    }

    @Test func preferenceKeyDefaults() {
        let keys = PreferenceKey.defaults.map(\.0)
        #expect(keys.contains(PreferenceKey.defaultRhythmMinutes))
        #expect(keys.contains(PreferenceKey.longBreakMinutes))
        #expect(keys.contains(PreferenceKey.rhythmDurationOptions))
        #expect(!keys.contains("shortBreakMinutes"))
    }

    @Test func timeFormattingDuration() {
        #expect(TimeFormatting.formatDuration(seconds: 0) == "0m")
        #expect(TimeFormatting.formatDuration(seconds: 300) == "5m")
        #expect(TimeFormatting.formatDuration(seconds: 3600) == "1h 0m")
        #expect(TimeFormatting.formatDuration(seconds: 5400) == "1h 30m")
    }

    @Test func timeFormattingTimer() {
        #expect(TimeFormatting.formatTimer(seconds: 0) == "0:00")
        #expect(TimeFormatting.formatTimer(seconds: 65) == "1:05")
        #expect(TimeFormatting.formatTimer(seconds: 3661) == "1:01:01")
    }

    // MARK: - TimerCompletionContext.CompletionType

    @Test func completionTypeTimeboundExpiry() {
        let type = TimerCompletionContext.CompletionType.timeboundExpiry
        #expect(type.isBreakExpiry == false)
        #expect(type.isTimeboundBreakExpiry == false)
        #expect(type.isFocusExpiry == false)
    }

    @Test func completionTypeRhythmFocusExpiry() {
        let type = TimerCompletionContext.CompletionType.rhythmFocusExpiry(
            breakMinutes: 5, isLongBreak: false
        )
        #expect(type.isBreakExpiry == false)
        #expect(type.isTimeboundBreakExpiry == false)
        #expect(type.isFocusExpiry == true)
    }

    @Test func completionTypeRhythmBreakExpiry() {
        let type = TimerCompletionContext.CompletionType.rhythmBreakExpiry(
            previousActivityId: 1, previousActivityTitle: "Writing",
            previousTimerMinutes: 25, previousBreakMinutes: 5
        )
        #expect(type.isBreakExpiry == true)
        #expect(type.isTimeboundBreakExpiry == false)
        #expect(type.isFocusExpiry == false)
    }

    @Test func completionTypeTimeboundBreakExpiry() {
        let type = TimerCompletionContext.CompletionType.timeboundBreakExpiry(
            recentActivityId: 1, recentActivityTitle: "Design",
            recentTimerMinutes: 30, recentSessionType: .timebound
        )
        #expect(type.isBreakExpiry == true)
        #expect(type.isTimeboundBreakExpiry == true)
        #expect(type.isFocusExpiry == false)
    }

    @Test func completionTypeTimeboundBreakExpiryWithNilFields() {
        let type = TimerCompletionContext.CompletionType.timeboundBreakExpiry(
            recentActivityId: nil, recentActivityTitle: nil,
            recentTimerMinutes: nil, recentSessionType: nil
        )
        #expect(type.isBreakExpiry == true)
        #expect(type.isTimeboundBreakExpiry == true)
        #expect(type.isFocusExpiry == false)
    }

    @Test func completionTypeMutualExclusivity() {
        let allTypes: [TimerCompletionContext.CompletionType] = [
            .timeboundExpiry,
            .rhythmFocusExpiry(breakMinutes: 5, isLongBreak: false),
            .rhythmBreakExpiry(previousActivityId: 1, previousActivityTitle: "Test",
                               previousTimerMinutes: 25, previousBreakMinutes: 5),
            .timeboundBreakExpiry(recentActivityId: nil, recentActivityTitle: nil,
                                  recentTimerMinutes: nil, recentSessionType: nil)
        ]

        for type in allTypes {
            // isFocusExpiry and isBreakExpiry are always mutually exclusive
            #expect(!(type.isFocusExpiry && type.isBreakExpiry))
            // isTimeboundBreakExpiry implies isBreakExpiry
            if type.isTimeboundBreakExpiry {
                #expect(type.isBreakExpiry == true)
            }
        }
    }
}
