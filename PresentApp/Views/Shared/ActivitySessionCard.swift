import SwiftUI
import PresentCore

/// Unified activity/session breakdown card used by Dashboard and Reports.
///
/// Renders sessions grouped by activity (with colored dots, state icons, expand/collapse)
/// or as a flat chronological list. Includes search and group-by controls.
struct ActivitySessionCard: View {
    let title: String
    let sessionEntries: [(Session, Activity)]
    let activityColorMap: [String: Color]
    var dayPortions: [Int64: Int] = [:]
    var includeActiveSession: Bool = false
    var onReload: (() -> Void)?

    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    @State private var searchText = ""
    @State private var grouping: SessionGrouping = .activity
    @State private var sortOrder: ActivitySortOrder = .timeSpent
    @State private var expandedActivities: Set<Int64> = []
    @State private var activePreMidnightSeconds: Int?

    // MARK: - Body

    var body: some View {
        ChartCard(title: title) {
            Picker("Sort", selection: $sortOrder) {
                ForEach(ActivitySortOrder.allCases, id: \.self) { order in
                    Text(order.displayName).tag(order)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
        } content: {
            if sessionEntries.isEmpty && !hasActiveSession {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "list.bullet",
                    description: Text("No sessions recorded for this period.")
                )
                .emptyStateStyle()
            } else {
                VStack(spacing: 0) {
                    searchBar
                    Divider()
                    controlsBar
                    Divider()

                    let entries = filteredEntries
                    if entries.isEmpty && !hasActiveSessionMatchingSearch {
                        ContentUnavailableView(
                            "No Matches",
                            systemImage: "magnifyingglass",
                            description: Text("No sessions match \"\(searchText)\".")
                        )
                        .emptyStateStyle()
                    } else {
                        switch grouping {
                        case .activity:
                            groupedView(entries: entries)
                        case .none:
                            ungroupedView(entries: entries)
                        }
                    }
                }
            }
        }
        .task(id: appState.currentSession?.id) {
            await loadActivePreMidnightSeconds()
        }
    }

    // MARK: - Active Session

    private var hasActiveSession: Bool {
        includeActiveSession && appState.isSessionActive && appState.currentSession != nil
    }

    /// Whether the active session matches the current search filter.
    private var hasActiveSessionMatchingSearch: Bool {
        guard hasActiveSession else { return false }
        return activeSessionMatchesSearch
    }

    private var activeSessionMatchesSearch: Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return true }
        if let activity = appState.currentActivity, activity.title.lowercased().contains(trimmed) { return true }
        if let session = appState.currentSession {
            if let note = session.note, note.lowercased().contains(trimmed) { return true }
            if let ticketId = session.ticketId, ticketId.lowercased().contains(trimmed) { return true }
        }
        return false
    }

    // MARK: - Filtered Entries

    private var filteredEntries: [(Session, Activity)] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return sessionEntries }
        return sessionEntries.filter { session, activity in
            if let note = session.note, note.lowercased().contains(trimmed) { return true }
            if let ticketId = session.ticketId, ticketId.lowercased().contains(trimmed) { return true }
            if activity.title.lowercased().contains(trimmed) { return true }
            return false
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Search notes, tickets, activities...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.subheadline)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Constants.spacingCard)
        .padding(.vertical, Constants.spacingCompact)
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        HStack {
            Text("Group by:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("Group by", selection: $grouping) {
                ForEach(SessionGrouping.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .labelsHidden()

            Spacer()
        }
        .padding(.horizontal, Constants.spacingCard)
        .padding(.vertical, Constants.spacingCompact)
    }

    // MARK: - Grouped View

    private func groupedView(entries: [(Session, Activity)]) -> some View {
        let groups = groupedEntries(from: entries)
        return VStack(spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.element.activity.id) { index, group in
                let activityId = group.activity.id ?? -1
                let isExpanded = expandedActivities.contains(activityId)
                let activeSession: Session? = hasActiveSession && appState.currentSession?.activityId == activityId
                    ? appState.currentSession : nil
                let totalCount = group.sessions.count + (activeSession != nil ? 1 : 0)
                let sessions = group.sessions.map(\.0)

                VStack(spacing: 0) {
                    // Activity header
                    HStack {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))

                        Circle()
                            .fill(activityColorMap[group.activity.title] ?? .secondary)
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.activity.title)
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

                        Text(TimeFormatting.formatDuration(seconds: groupTotalSeconds(group: group, activeSession: activeSession)))
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
                        // Active session row
                        if let active = activeSession, activeSessionMatchesSearch {
                            activeSessionRow(session: active, activityTitle: group.activity.title)
                        }

                        // Completed/cancelled sessions
                        ForEach(group.sessions, id: \.0.id) { session, _ in
                            completedSessionRow(session: session, activityTitle: group.activity.title)
                        }
                    }
                }
            }
        }
        .padding(.bottom, Constants.spacingCard)
    }

    // MARK: - Ungrouped View

    private func ungroupedView(entries: [(Session, Activity)]) -> some View {
        VStack(spacing: 0) {
            // Active session at top when ungrouped
            if hasActiveSession, activeSessionMatchesSearch,
               let active = appState.currentSession, let activity = appState.currentActivity {
                activeSessionRow(session: active, activityTitle: activity.title)
                    .background(Color.gray.opacity(entries.isEmpty ? 0 : 0.08))
            }

            ForEach(Array(entries.enumerated()), id: \.element.0.id) { index, entry in
                let adjustedIndex = hasActiveSessionMatchingSearch ? index + 1 : index
                SessionRow(session: entry.0, activityTitle: entry.1.title)
                    .padding(.horizontal, Constants.spacingCard)
                    .padding(.vertical, Constants.spacingCompact)
                    .background(adjustedIndex.isMultiple(of: 2) ? Color.clear : Color.gray.opacity(0.08))
                    .contentShape(Rectangle())
                    .sessionContextMenu(session: entry.0, activityTitle: entry.1.title) {
                        onReload?()
                    }
            }
        }
        .padding(.bottom, Constants.spacingCard)
    }

    // MARK: - Session Rows

    @ViewBuilder
    private func activeSessionRow(session: Session, activityTitle: String) -> some View {
        HStack(spacing: Constants.spacingCompact) {
            SpinningClockIcon(isRunning: session.state == .running)

            VStack(alignment: .leading, spacing: 2) {
                Text(sessionTypeLabel(session))
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text(TimeFormatting.formatTime(session.startedAt, referenceDate: Date()))
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
        .padding(.leading, grouping == .activity ? 20 : 0)
        .background(Color.gray.opacity(0.04))
        .contentShape(Rectangle())
        .sessionContextMenu(session: session, activityTitle: activityTitle)
    }

    @ViewBuilder
    private func completedSessionRow(session: Session, activityTitle: String) -> some View {
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
        .sessionContextMenu(session: session, activityTitle: activityTitle) {
            onReload?()
        }
    }

    // MARK: - Grouping Logic

    private func groupedEntries(from entries: [(Session, Activity)]) -> [(activity: Activity, sessions: [(Session, Activity)], totalSeconds: Int)] {
        var groups: [Int64: (activity: Activity, sessions: [(Session, Activity)])] = [:]
        var order: [Int64] = []

        for entry in entries {
            let activityId = entry.1.id ?? -1
            if groups[activityId] == nil {
                groups[activityId] = (activity: entry.1, sessions: [])
                order.append(activityId)
            }
            groups[activityId]?.sessions.append(entry)
        }

        // Include active session's activity even if not in completed entries (cross-midnight)
        if hasActiveSession, activeSessionMatchesSearch,
           let activity = appState.currentActivity,
           let activityId = activity.id,
           groups[activityId] == nil {
            groups[activityId] = (activity: activity, sessions: [])
            order.append(activityId)
        }

        var result = order.compactMap { id -> (activity: Activity, sessions: [(Session, Activity)], totalSeconds: Int)? in
            guard let group = groups[id] else { return nil }
            let sorted = group.sessions.sorted { ($0.0.endedAt ?? .distantFuture) > ($1.0.endedAt ?? .distantFuture) }
            let total = sorted.reduce(0) { sum, entry in
                if let sessionId = entry.0.id, let todayPortion = dayPortions[sessionId] {
                    return sum + TimeFormatting.floorToMinute(todayPortion)
                }
                return sum + TimeFormatting.floorToMinute(entry.0.durationSeconds ?? 0)
            }
            return (activity: group.activity, sessions: sorted, totalSeconds: total)
        }

        switch sortOrder {
        case .timeSpent:
            result.sort { lhs, rhs in
                let lhsActive = hasActiveSession && appState.currentSession?.activityId == lhs.activity.id
                let rhsActive = hasActiveSession && appState.currentSession?.activityId == rhs.activity.id
                let lhsTotal = lhs.totalSeconds + (lhsActive ? activeElapsedSeconds(for: lhs.activity.id ?? -1) : 0)
                let rhsTotal = rhs.totalSeconds + (rhsActive ? activeElapsedSeconds(for: rhs.activity.id ?? -1) : 0)
                return lhsTotal > rhsTotal
            }
        case .mostRecent:
            result.sort { lhs, rhs in
                latestSessionDate(for: lhs) > latestSessionDate(for: rhs)
            }
        case .alphabetical:
            result.sort { $0.activity.title.localizedCaseInsensitiveCompare($1.activity.title) == .orderedAscending }
        }

        return result
    }

    // MARK: - Duration Helpers

    private func groupTotalSeconds(group: (activity: Activity, sessions: [(Session, Activity)], totalSeconds: Int), activeSession: Session?) -> Int {
        let activityId = group.activity.id ?? -1
        return group.totalSeconds + TimeFormatting.floorToMinute(activeElapsedSeconds(for: activityId))
    }

    private func activeElapsedSeconds(for activityId: Int64) -> Int {
        guard let session = appState.currentSession,
              session.activityId == activityId,
              appState.isSessionActive else { return 0 }
        if let preMidnight = activePreMidnightSeconds {
            return max(0, appState.timerElapsedSeconds - preMidnight)
        }
        return appState.timerElapsedSeconds
    }

    private func latestSessionDate(for group: (activity: Activity, sessions: [(Session, Activity)], totalSeconds: Int)) -> Date {
        let activityId = group.activity.id ?? -1
        var latest: Date = .distantPast
        if let current = appState.currentSession, current.activityId == activityId {
            latest = current.startedAt
        }
        if let first = group.sessions.first {
            latest = max(latest, first.0.startedAt)
        }
        return latest
    }

    // MARK: - Session Display Helpers

    private func activityTimeRange(_ sessions: [Session], active: Session?) -> String? {
        var starts: [Date] = sessions.map(\.startedAt)
        let ends: [Date] = sessions.compactMap(\.endedAt)
        if let active {
            starts.append(active.startedAt)
        }
        guard let first = starts.min() else { return nil }
        let today = Date()
        if let last = ends.max() {
            return "\(TimeFormatting.formatTime(first, referenceDate: today)) \u{2013} \(TimeFormatting.formatTime(last, referenceDate: today))"
        }
        return TimeFormatting.formatTime(first, referenceDate: today)
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

    @ViewBuilder
    private func sessionDurationLabel(_ session: Session) -> some View {
        if let total = session.durationSeconds {
            if let id = session.id, let todayPortion = dayPortions[id] {
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

    // MARK: - Cross-Midnight

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
