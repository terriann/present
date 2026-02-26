import SwiftUI
import PresentCore

struct ActivityBreakdownCard: View {
    let activityColorMap: [String: Color]
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var expandedActivities: Set<Int64> = []
    @State private var todaySessions: [Int64: [Session]] = [:]
    @State private var todayPortions: [Int64: Int] = [:]
    /// Pre-midnight active seconds for a cross-midnight active session; computed once from segments.
    @State private var activePreMidnightSeconds: Int?

    /// Includes the active session's activity even if it's not in DB summaries (cross-midnight).
    private var displayActivities: [ActivitySummary] {
        var activities = appState.todayActivities
        if appState.isSessionActive,
           let activity = appState.currentActivity,
           !activities.contains(where: { $0.activity.id == activity.id }) {
            activities.append(ActivitySummary(activity: activity, totalSeconds: 0, sessionCount: 0))
        }
        return activities
    }

    var body: some View {
        ChartCard(title: "Today's Activities") {
            if displayActivities.isEmpty {
                ContentUnavailableView(
                    "No Activities",
                    systemImage: "list.bullet",
                    description: Text("No activities recorded for this period.")
                )
                .emptyStateStyle()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(displayActivities.enumerated()), id: \.element.activity.id) { index, summary in
                        let activityId = summary.activity.id ?? -1
                        let isExpanded = expandedActivities.contains(activityId)
                        let sessions = todaySessions[activityId]
                        let activeSession: Session? = appState.currentSession?.activityId == activityId ? appState.currentSession : nil
                        let totalCount = summary.sessionCount + (activeSession != nil ? 1 : 0)

                        VStack(spacing: 0) {
                            HStack {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .rotationEffect(.degrees(isExpanded ? 90 : 0))

                                Circle()
                                    .fill(activityColorMap[summary.activity.title] ?? .secondary)
                                    .frame(width: 8, height: 8)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(summary.activity.title)
                                        .font(.title3)
                                        .lineLimit(1)

                                    HStack(spacing: 4) {
                                        Text("\(totalCount) \(totalCount == 1 ? "session" : "sessions")")
                                        if let range = activityTimeRange(sessions, active: activeSession) {
                                            Text("\u{00B7}")
                                            Text(range)
                                        }
                                    }
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if activeSession?.state == .running {
                                    SpinningClockIcon(isRunning: true)
                                }

                                Text(TimeFormatting.formatDuration(seconds: roundedTotalSeconds(for: activityId, baseTotalSeconds: summary.totalSeconds)))
                                    .font(.durationValue)
                                    .foregroundStyle(activeSession != nil ? theme.accent : .secondary)
                                    .contentTransition(.numericText())
                            }
                            .padding(.vertical, Constants.spacingCompact)
                            .padding(.horizontal, Constants.spacingCard)
                            .background(index.isMultiple(of: 2) ? Color.clear : Color.gray.opacity(0.08))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAdaptiveAnimation(.easeInOut(duration: 0.2)) {
                                    if isExpanded {
                                        expandedActivities.remove(activityId)
                                    } else {
                                        expandedActivities.insert(activityId)
                                    }
                                }
                            }

                            if isExpanded {
                                // Active session row (if any)
                                if let active = activeSession {
                                    HStack(spacing: Constants.spacingCompact) {
                                        SpinningClockIcon(isRunning: activeSession?.state == .running)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(sessionTypeLabel(active))
                                                .font(.body)
                                                .foregroundStyle(.secondary)
                                            Text(TimeFormatting.formatTime(active.startedAt, referenceDate: Date()))
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if let preMidnight = activePreMidnightSeconds {
                                            HStack(spacing: 0) {
                                                Text(TimeFormatting.formatDuration(seconds: max(0, appState.timerElapsedSeconds - preMidnight)))
                                                    .font(.durationDetail)
                                                    .foregroundStyle(theme.accent)
                                                    .contentTransition(.numericText())
                                                Text(" / \(TimeFormatting.formatDuration(seconds: appState.timerElapsedSeconds))")
                                                    .font(.durationDetail)
                                                    .foregroundStyle(theme.accent.opacity(0.5))
                                                    .contentTransition(.numericText())
                                            }
                                        } else {
                                            Text(TimeFormatting.formatDuration(seconds: appState.timerElapsedSeconds))
                                                .font(.durationDetail)
                                                .foregroundStyle(theme.accent)
                                                .contentTransition(.numericText())
                                        }
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, Constants.spacingCard)
                                    .padding(.leading, 20)
                                    .background(Color.gray.opacity(0.04))
                                    .contentShape(Rectangle())
                                    .sessionContextMenu(session: active, activityTitle: summary.activity.title)
                                }

                                // Completed/cancelled sessions
                                if let sessions {
                                    ForEach(sessions) { session in
                                    HStack(spacing: Constants.spacingCompact) {
                                        stateIcon(for: session)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(sessionTypeLabel(session))
                                                .font(.body)
                                                .foregroundStyle(.secondary)

                                            Text(sessionTimeRange(session))
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        sessionDurationLabel(session)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, Constants.spacingCard)
                                    .padding(.leading, 20)
                                    .background(Color.gray.opacity(0.04))
                                    .contentShape(Rectangle())
                                    .sessionContextMenu(session: session, activityTitle: summary.activity.title) {
                                        todaySessions[activityId] = nil
                                        loadSessionsForActivity(activityId)
                                    }
                                }
                            }
                            }
                        }
                    }
                }
                .padding(.bottom, Constants.spacingCard)
            }
        }
        .task(id: displayActivities.map { $0.activity.id }) {
            for summary in displayActivities {
                if let id = summary.activity.id {
                    loadSessionsForActivity(id)
                }
            }
        }
        .task(id: appState.currentSession?.id) {
            await loadActivePreMidnightSeconds()
        }
    }

    // MARK: - Helpers

    private func activityTimeRange(_ sessions: [Session]?, active: Session?) -> String? {
        var starts: [Date] = sessions?.map(\.startedAt) ?? []
        let ends: [Date] = sessions?.compactMap(\.endedAt) ?? []
        if let active {
            starts.append(active.startedAt)
            // active session has no endedAt — omit end so range shows open start
        }
        guard let first = starts.min() else { return nil }
        let today = Date()
        if let last = ends.max() {
            return "\(TimeFormatting.formatTime(first, referenceDate: today)) \u{2013} \(TimeFormatting.formatTime(last, referenceDate: today))"
        }
        // Only active session (no completed end times yet)
        return TimeFormatting.formatTime(first, referenceDate: today)
    }

    /// Returns the active session's today-portion elapsed seconds for a given activity, or 0 if not active.
    private func activeElapsedSeconds(for activityId: Int64) -> Int {
        guard let session = appState.currentSession,
              session.activityId == activityId,
              appState.isSessionActive else { return 0 }
        if let preMidnight = activePreMidnightSeconds {
            return max(0, appState.timerElapsedSeconds - preMidnight)
        }
        return appState.timerElapsedSeconds
    }

    /// Computes the activity total by rounding each session to the minute before summing,
    /// so the total matches the individually displayed durations.
    private func roundedTotalSeconds(for activityId: Int64, baseTotalSeconds: Int) -> Int {
        guard let sessions = todaySessions[activityId] else { return baseTotalSeconds }
        let completedTotal = sessions.reduce(0) { sum, session in
            if let id = session.id, let todayPortion = todayPortions[id] {
                return sum + TimeFormatting.floorToMinute(todayPortion)
            }
            return sum + TimeFormatting.floorToMinute(session.durationSeconds ?? 0)
        }
        return completedTotal + TimeFormatting.floorToMinute(activeElapsedSeconds(for: activityId))
    }

    private func sessionTypeLabel(_ session: Session) -> String {
        let base = SessionTypeConfig.config(for: session.sessionType).displayName
        switch session.sessionType {
        case .timebound:
            if let minutes = session.timerLengthMinutes {
                return "\(base) \u{00B7} \(minutes)m"
            }
        case .rhythm:
            if let work = session.timerLengthMinutes, let brk = session.breakMinutes {
                return "\(base) \u{00B7} \(RhythmOption(focusMinutes: work, breakMinutes: brk).displayLabel)"
            }
        case .work:
            break
        }
        return base
    }

    private func sessionTimeRange(_ session: Session) -> String {
        let today = Date()
        let start = TimeFormatting.formatTime(session.startedAt, referenceDate: today)
        guard let end = session.endedAt else { return start }
        return "\(start) \u{2013} \(TimeFormatting.formatTime(end, referenceDate: today))"
    }

    private func isSessionComplete(_ session: Session) -> Bool {
        switch (session.state, session.sessionType) {
        case (.cancelled, _):
            return false
        case (.completed, .work):
            return true
        case (.completed, .rhythm), (.completed, .timebound):
            return session.timerLengthMinutes
                .flatMap { target in session.durationSeconds.map { $0 >= target * 60 } } ?? false
        default:
            return false
        }
    }

    @ViewBuilder
    private func stateIcon(for session: Session) -> some View {
        let complete = isSessionComplete(session)
        Image(systemName: complete ? "checkmark.circle" : "exclamationmark.circle")
            .font(.body)
            .foregroundStyle(.tertiary)
            .help(complete ? "Completed" : "Ended early")
    }

    /// Duration label for a completed session. Shows "todayPortion / total" when the session
    /// crosses midnight, with the slash and total at reduced opacity.
    @ViewBuilder
    private func sessionDurationLabel(_ session: Session) -> some View {
        if let total = session.durationSeconds {
            if let id = session.id, let todayPortion = todayPortions[id] {
                HStack(spacing: 0) {
                    Text(TimeFormatting.formatDuration(seconds: todayPortion))
                        .font(.durationDetail)
                        .foregroundStyle(.secondary)
                    Text(" / \(TimeFormatting.formatDuration(seconds: total))")
                        .font(.durationDetail)
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            } else {
                Text(TimeFormatting.formatDuration(seconds: total))
                    .font(.durationDetail)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadSessionsForActivity(_ activityId: Int64) {
        guard todaySessions[activityId] == nil else { return }
        Task {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: Date())
            guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }
            do {
                let sessions = try await appState.service.listSessions(
                    from: startOfDay, to: endOfDay,
                    type: nil, activityId: activityId, includeArchived: false
                )
                let sorted = sessions.map(\.0).sorted {
                    ($0.endedAt ?? .distantFuture) > ($1.endedAt ?? .distantFuture)
                }
                todaySessions[activityId] = sorted

                // Compute segment-based today portions for cross-midnight sessions
                let crossMidnightIds = sorted.compactMap { session -> Int64? in
                    guard let id = session.id,
                          !Calendar.current.isDateInToday(session.startedAt) else { return nil }
                    return id
                }
                if !crossMidnightIds.isEmpty {
                    let portions = try await appState.service.sessionDayPortions(
                        sessionIds: crossMidnightIds, date: Date()
                    )
                    for (id, secs) in portions {
                        todayPortions[id] = secs
                    }
                }
            } catch {
                // Fail silently
            }
        }
    }

    private func loadActivePreMidnightSeconds() async {
        guard let session = appState.currentSession,
              let sessionId = session.id,
              !Calendar.current.isDateInToday(session.startedAt) else {
            activePreMidnightSeconds = nil
            return
        }
        do {
            let portions = try await appState.service.sessionDayPortions(
                sessionIds: [sessionId], date: Date()
            )
            let todayFromSegments = portions[sessionId] ?? 0
            activePreMidnightSeconds = max(0, appState.timerElapsedSeconds - todayFromSegments)
        } catch {
            activePreMidnightSeconds = nil
        }
    }
}
