import Testing
import Foundation
@testable import PresentCore

@Suite("Model Tests")
struct ModelTests {

    @Test func sessionTypeRawValues() {
        #expect(SessionType.work.rawValue == "work")
        #expect(SessionType.rhythm.rawValue == "rhythm")
        #expect(SessionType.timebound.rawValue == "timebound")
        #expect(SessionType.timebox.rawValue == "timebox")
    }

    @Test func sessionStateRawValues() {
        #expect(SessionState.running.rawValue == "running")
        #expect(SessionState.paused.rawValue == "paused")
        #expect(SessionState.completed.rawValue == "completed")
        #expect(SessionState.cancelled.rawValue == "cancelled")
    }

    @Test func sessionTypeConfigs() {
        #expect(SessionTypeConfig.all.count == 4)
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
        #expect(PreferenceKey.defaults.count == 6)
        let keys = PreferenceKey.defaults.map(\.0)
        #expect(keys.contains(PreferenceKey.defaultRhythmMinutes))
        #expect(keys.contains(PreferenceKey.shortBreakMinutes))
        #expect(keys.contains(PreferenceKey.longBreakMinutes))
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
}
