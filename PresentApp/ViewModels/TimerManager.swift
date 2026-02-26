import SwiftUI
import PresentCore

@MainActor @Observable
final class TimerManager {
    // MARK: - Timer State

    var timerElapsedSeconds: Int = 0
    private var timerTask: Task<Void, Never>?
    private var timerCompletionHandled = false

    // MARK: - Completed Timer Linger

    var completedTimerText: String?
    var isCompletedTimerFading: Bool = false
    private var completedTimerLingerTask: Task<Void, Never>?

    // MARK: - Timer Completion Alert

    var timerCompletionContext: TimerCompletionContext?

    /// Saved when starting a break so the break-end alert knows what to resume.
    /// Also persisted to UserDefaults so it survives crashes/force-quits.
    var breakPrecedingContext: (activityId: Int64, title: String, timerMinutes: Int, breakMinutes: Int)? {
        didSet {
            if let ctx = breakPrecedingContext {
                persistBreakContext(ctx)
            } else {
                UserDefaults.standard.removeObject(forKey: "breakPrecedingContext")
            }
        }
    }

    // MARK: - Session Reference

    /// Set by AppState whenever session state changes. Allows timer tick and
    /// formattedTimerValue to read session info without callbacks.
    var currentSession: Session?

    // MARK: - Callback

    /// Called from the timer tick loop when a countdown finishes.
    /// AppState sets this to its own `handleTimerCompletion()`.
    var onCountdownCompleted: (() async -> Void)?

    // MARK: - Dependencies

    private let service: PresentService

    // MARK: - Computed Properties

    var formattedTimerValue: String {
        guard let session = currentSession else { return "0:00" }

        // For countdown timers, show remaining time
        if let timerMinutes = session.timerLengthMinutes,
           session.sessionType == .rhythm || session.sessionType == .timebound {
            let totalSeconds = timerMinutes * 60
            let remaining = max(0, totalSeconds - timerElapsedSeconds)
            return TimeFormatting.formatTimer(seconds: remaining)
        }

        // For work sessions, show elapsed time
        return TimeFormatting.formatTimer(seconds: timerElapsedSeconds)
    }

    // MARK: - Initialization

    init(service: PresentService) {
        self.service = service
    }

    // MARK: - Timer Control

    func startTimer(session: Session) {
        stopTimer()
        currentSession = session

        let elapsed = Int(Date().timeIntervalSince(session.startedAt)) - session.totalPausedSeconds
        timerElapsedSeconds = max(0, elapsed)
        timerCompletionHandled = false

        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                guard let session = self.currentSession, session.state == .running else { return }
                let elapsed = Int(Date().timeIntervalSince(session.startedAt)) - session.totalPausedSeconds
                self.timerElapsedSeconds = max(0, elapsed)

                // Check for countdown timer completion
                if !self.timerCompletionHandled,
                   let timerMinutes = session.timerLengthMinutes,
                   (session.sessionType == .rhythm || session.sessionType == .timebound) {
                    let totalSeconds = timerMinutes * 60
                    if self.timerElapsedSeconds >= totalSeconds {
                        self.timerCompletionHandled = true
                        await self.onCountdownCompleted?()
                    }
                }
            }
        }
    }

    func stopTimer(resetElapsed: Bool = true) {
        timerTask?.cancel()
        timerTask = nil
        if resetElapsed {
            timerElapsedSeconds = 0
        }
    }

    /// Update elapsed seconds for a paused session without starting the tick loop.
    func syncPausedElapsed(session: Session) {
        if let pausedAt = session.lastPausedAt {
            let activeTime = Int(pausedAt.timeIntervalSince(session.startedAt)) - session.totalPausedSeconds
            timerElapsedSeconds = max(0, activeTime)
        }
    }

    var isTimerRunning: Bool {
        timerTask != nil
    }

    // MARK: - Completed Timer Linger

    func startCompletedTimerLinger(text: String, isCountdown: Bool) {
        clearCompletedTimerLinger()
        completedTimerText = text
        isCompletedTimerFading = false

        completedTimerLingerTask = Task {
            try? await Task.sleep(for: .seconds(Constants.completedTimerLingerSeconds))
            guard !Task.isCancelled else { return }

            isCompletedTimerFading = true
            completedTimerText = nil

            clearCompletedTimerLinger()
        }
    }

    func clearCompletedTimerLinger() {
        completedTimerLingerTask?.cancel()
        completedTimerLingerTask = nil
        completedTimerText = nil
        isCompletedTimerFading = false
    }

    // MARK: - Break Context Persistence

    func restoreBreakContextIfNeeded() {
        guard breakPrecedingContext == nil else { return }
        guard let dict = UserDefaults.standard.dictionary(forKey: "breakPrecedingContext"),
              let activityId = dict["activityId"] as? Int64,
              let title = dict["title"] as? String,
              let timerMinutes = dict["timerMinutes"] as? Int,
              let breakMinutes = dict["breakMinutes"] as? Int else { return }
        // Set directly to avoid re-persisting via didSet
        breakPrecedingContext = (activityId: activityId, title: title,
                                timerMinutes: timerMinutes, breakMinutes: breakMinutes)
    }

    private func persistBreakContext(
        _ ctx: (activityId: Int64, title: String, timerMinutes: Int, breakMinutes: Int)
    ) {
        let dict: [String: Any] = [
            "activityId": ctx.activityId,
            "title": ctx.title,
            "timerMinutes": ctx.timerMinutes,
            "breakMinutes": ctx.breakMinutes,
        ]
        UserDefaults.standard.set(dict, forKey: "breakPrecedingContext")
    }

    // MARK: - Preference Resolvers

    func resolveBreakMinutes(session: Session, sessionIndex: Int) async -> Int {
        let cycleLength = await resolveCycleLength()
        let isLong = sessionIndex >= cycleLength

        if isLong {
            if let val = try? await service.getPreference(key: PreferenceKey.longBreakMinutes) {
                return Int(val) ?? Constants.longBreakMinutes
            }
            return Constants.longBreakMinutes
        }
        return session.breakMinutes ?? Constants.defaultShortBreakMinutes
    }

    func resolveCycleLength() async -> Int {
        if let val = try? await service.getPreference(key: PreferenceKey.rhythmCycleLength) {
            return Int(val) ?? Constants.rhythmCycleLength
        }
        return Constants.rhythmCycleLength
    }
}
