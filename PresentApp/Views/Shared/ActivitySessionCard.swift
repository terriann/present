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
    /// Reference date for time annotations. When set, day-of-week is shown only for times on a
    /// different calendar day (single-day mode). When nil, start times always include the day and
    /// end times annotate only when they fall on a different day than the start (multi-day mode).
    var timeReferenceDate: Date? = Date()
    var resetToken: AnyHashable?
    var onReload: (() -> Void)?

    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var searchText = ""
    @State private var grouping: SessionGrouping = .activity
    @State private var sortOrder: ActivitySortOrder = .mostRecent
    @State private var sortInitialized = false
    @State private var expandedActivities: Set<Int64> = []
    @State private var editingSessionId: Int64?
    @State private var activePreMidnightSeconds: Int?

    // MARK: - Body

    var body: some View {
        ChartCard(title: title) {
            if sessionEntries.isEmpty && !hasActiveSession {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "list.bullet",
                    description: Text("No sessions recorded for this period.")
                )
                .emptyStateStyle()
            } else {
                VStack(spacing: 0) {
                    toolbar
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
        .onChange(of: appState.isSessionActive) { _, isActive in
            sortOrder = isActive ? .mostRecent : .timeSpent
        }
        .onChange(of: searchText) { clearEditing() }
        .onChange(of: sortOrder) { clearEditing() }
        .onChange(of: grouping) { clearEditing() }
        .onChange(of: resetToken) {
            expandedActivities.removeAll()
        }
        .onAppear {
            guard !sortInitialized else { return }
            sortInitialized = true
            sortOrder = appState.isSessionActive ? .mostRecent : .timeSpent
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

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(alignment: .bottom, spacing: Constants.spacingCard) {
            // Search field fills available space
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .accessibilityLabel("Search sessions")
                    .onKeyPress(.escape) {
                        searchText = ""
                        return .handled
                    }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                    .help("Clear search")
                }
            }

            // Sort dropdown with label above
            VStack(alignment: .leading, spacing: 2) {
                Text("Sort")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Picker("Sort", selection: $sortOrder) {
                    ForEach(ActivitySortOrder.allCases, id: \.self) { order in
                        Text(order.displayName).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .labelsHidden()
            }

            // Group-by dropdown with label above
            VStack(alignment: .leading, spacing: 2) {
                Text("Group")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Picker("Group", selection: $grouping) {
                    ForEach(SessionGrouping.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .labelsHidden()
            }
        }
        .padding(.horizontal, Constants.spacingCard)
        .padding(.vertical, Constants.spacingCompact)
    }

    // MARK: - Grouped View

    private func groupedView(entries: [(Session, Activity)]) -> some View {
        let groups = groupedEntries(from: entries)
        return LazyVStack(spacing: 0) {
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

                            HStack(spacing: Constants.spacingCompact) {
                                HStack(spacing: Constants.spacingTight) {
                                    Text("\(totalCount) \(totalCount == 1 ? "session" : "sessions")")
                                    if let range = activityTimeRange(sessions, active: activeSession) {
                                        Text("\u{00B7}")
                                        Text(range)
                                    }
                                }

                                activityOwnBadge(activity: group.activity)

                                sessionOnlyBadges(activity: group.activity, sessions: sessions)
                                    .opacity(isExpanded ? 0 : 1)
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
                    .geometryGroup()
                    .padding(.vertical, Constants.spacingCompact)
                    .padding(.horizontal, Constants.spacingCard)
                    .background(index.isMultiple(of: 2) ? Color.clear : Constants.alternatingRowBackground)
                    .hoverHighlight()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        clearEditing()
                        withAdaptiveAnimation(.easeInOut(duration: 0.45)) {
                            if isExpanded {
                                expandedActivities.remove(activityId)
                            } else {
                                expandedActivities.insert(activityId)
                            }
                        }
                    }
                    .contextMenu {
                        Button {
                            appState.navigate(to: .showActivity(group.activity.id ?? -1))
                        } label: {
                            Label("Edit Activity", systemImage: "square.and.pencil")
                        }
                    }

                    if isExpanded {
                        let activeVisible = activeSession != nil && activeSessionMatchesSearch

                        // Active session row (sub-row index 0)
                        if let active = activeSession, activeSessionMatchesSearch {
                            if active.id == editingSessionId {
                                SessionInlineEditForm(session: active, activity: group.activity,
                                    timeReferenceDate: timeReferenceDate,
                                    onSave: { clearEditing(); onReload?() },
                                    onCancel: { clearEditing() })
                                    .padding(.horizontal, Constants.spacingCard)
                                    .padding(.vertical, Constants.spacingCompact)
                                    .background(subRowBackground(index: 0))
                            } else {
                                activeSessionRow(session: active, activityTitle: group.activity.title, activityExternalId: group.activity.externalId)
                                    .background(subRowBackground(index: 0))
                                    .hoverHighlight()
                                    .onTapGesture(count: 2) {
                                        guard let id = active.id, editingSessionId != id else { return }
                                        beginEditing(id)
                                    }
                                    .onTapGesture {
                                        guard editingSessionId != nil else { return }
                                        clearEditing()
                                    }
                            }
                        }

                        // Completed/cancelled sessions
                        ForEach(Array(group.sessions.enumerated()), id: \.element.0.id) { subIndex, entry in
                            let rowIndex = activeVisible ? subIndex + 1 : subIndex
                            if entry.0.id == editingSessionId {
                                SessionInlineEditForm(session: entry.0, activity: entry.1,
                                    timeReferenceDate: timeReferenceDate,
                                    onSave: { clearEditing(); onReload?() },
                                    onCancel: { clearEditing() })
                                    .padding(.horizontal, Constants.spacingCard)
                                    .padding(.vertical, Constants.spacingCompact)
                                    .background(subRowBackground(index: rowIndex))
                            } else {
                                completedSessionRow(session: entry.0, activityTitle: group.activity.title, activityExternalId: group.activity.externalId)
                                    .background(subRowBackground(index: rowIndex))
                                    .hoverHighlight()
                                    .onTapGesture(count: 2) {
                                        guard let id = entry.0.id, editingSessionId != id else { return }
                                        beginEditing(id)
                                    }
                                    .onTapGesture {
                                        guard editingSessionId != nil else { return }
                                        clearEditing()
                                    }
                            }
                        }
                    }
                }
            }
        }
        .padding(.bottom, Constants.spacingCard)
    }

    // MARK: - Ungrouped View

    private func ungroupedView(entries: [(Session, Activity)]) -> some View {
        LazyVStack(spacing: 0) {
            // Active session at top
            if hasActiveSession, activeSessionMatchesSearch,
               let active = appState.currentSession, let activity = appState.currentActivity {
                if active.id == editingSessionId {
                    SessionInlineEditForm(session: active, activity: activity,
                        timeReferenceDate: timeReferenceDate,
                        onSave: { clearEditing(); onReload?() },
                        onCancel: { clearEditing() })
                        .padding(.horizontal, Constants.spacingCard)
                        .padding(.vertical, Constants.spacingCompact)
                } else {
                    ungroupedActiveSessionRow(session: active, activity: activity)
                        .padding(.vertical, Constants.spacingCompact)
                        .padding(.horizontal, Constants.spacingCard)
                        .background(Color.clear)
                        .hoverHighlight()
                        .contentShape(Rectangle())
                        .sessionContextMenu(session: active, activityTitle: activity.title,
                            onEdit: { beginEditing($0) })
                        .onTapGesture(count: 2) {
                            guard let id = active.id, editingSessionId != id else { return }
                            beginEditing(id)
                        }
                        .onTapGesture {
                            guard editingSessionId != nil else { return }
                            clearEditing()
                        }
                }
            }

            ForEach(Array(entries.enumerated()), id: \.element.0.id) { index, entry in
                let adjustedIndex = hasActiveSessionMatchingSearch ? index + 1 : index
                if entry.0.id == editingSessionId {
                    SessionInlineEditForm(session: entry.0, activity: entry.1,
                        timeReferenceDate: timeReferenceDate,
                        onSave: { clearEditing(); onReload?() },
                        onCancel: { clearEditing() })
                        .padding(.horizontal, Constants.spacingCard)
                        .padding(.vertical, Constants.spacingCompact)
                } else {
                    ungroupedSessionRow(session: entry.0, activity: entry.1)
                        .padding(.vertical, Constants.spacingCompact)
                        .padding(.horizontal, Constants.spacingCard)
                        .background(adjustedIndex.isMultiple(of: 2) ? Color.clear : Constants.alternatingRowBackground)
                        .hoverHighlight()
                        .contentShape(Rectangle())
                        .sessionContextMenu(session: entry.0, activityTitle: entry.1.title,
                            onEdit: { beginEditing($0) }) {
                            onReload?()
                        }
                        .onTapGesture(count: 2) {
                            guard let id = entry.0.id, editingSessionId != id else { return }
                            beginEditing(id)
                        }
                        .onTapGesture {
                            guard editingSessionId != nil else { return }
                            clearEditing()
                        }
                }
            }
        }
        .padding(.bottom, Constants.spacingCard)
    }

    // MARK: - Session Rows

    /// Active session row for grouped view — leading SpinningClockIcon, type label, time, live duration.
    @ViewBuilder
    private func activeSessionRow(session: Session, activityTitle: String, activityExternalId: String? = nil) -> some View {
        HStack(spacing: Constants.spacingCompact) {
            SpinningClockIcon(isRunning: session.state == .running)

            VStack(alignment: .leading, spacing: 2) {
                Text(sessionTypeLabel(session))
                    .font(.body)
                    .foregroundStyle(.secondary)
                HStack(spacing: Constants.spacingCompact) {
                    Text(formatStartTime(session.startedAt))
                    sessionMetadataBadges(session, activityExternalId: activityExternalId)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()
            activeDurationLabel
        }
        .geometryGroup()
        .padding(.vertical, 6)
        .padding(.horizontal, Constants.spacingCard)
        .padding(.leading, 20)
        .contentShape(Rectangle())
        .sessionContextMenu(session: session, activityTitle: activityTitle,
            showEditActivity: false, onEdit: { beginEditing($0) })
    }

    /// Active session row for ungrouped view — SpinningClockIcon on left where the dot would be.
    @ViewBuilder
    private func ungroupedActiveSessionRow(session: Session, activity: Activity) -> some View {
        HStack(spacing: Constants.spacingCompact) {
            SpinningClockIcon(isRunning: session.state == .running)

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.body.bold())

                HStack(spacing: Constants.spacingCompact) {
                    HStack(spacing: Constants.spacingTight) {
                        Text(sessionTypeLabel(session))
                        Text("\u{00B7}")
                        Text(formatStartTime(session.startedAt))
                    }
                    sessionMetadataBadges(session, activityExternalId: activity.externalId)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            activeDurationLabel
        }
        .geometryGroup()
        .padding(.vertical, 2)
    }

    /// Completed/cancelled session row for ungrouped view — colored dot on left, no trailing icon.
    @ViewBuilder
    private func ungroupedSessionRow(session: Session, activity: Activity) -> some View {
        HStack(spacing: Constants.spacingCompact) {
            Circle()
                .fill(activityColorMap[activity.title] ?? .secondary)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.body.bold())

                HStack(spacing: Constants.spacingCompact) {
                    HStack(spacing: Constants.spacingTight) {
                        Text(sessionTypeLabel(session))
                        Text("\u{00B7}")
                        Text(sessionTimeRange(session))
                    }
                    sessionMetadataBadges(session, activityExternalId: activity.externalId)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            sessionDurationLabel(session)
        }
        .geometryGroup()
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func completedSessionRow(session: Session, activityTitle: String, activityExternalId: String? = nil) -> some View {
        HStack(spacing: Constants.spacingCompact) {
            stateIcon(for: session)

            VStack(alignment: .leading, spacing: 2) {
                Text(sessionTypeLabel(session))
                    .font(.body)
                    .foregroundStyle(.secondary)

                HStack(spacing: Constants.spacingCompact) {
                    Text(sessionTimeRange(session))
                    sessionMetadataBadges(session, activityExternalId: activityExternalId)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            sessionDurationLabel(session)
        }
        .geometryGroup()
        .padding(.vertical, 6)
        .padding(.horizontal, Constants.spacingCard)
        .padding(.leading, 20)
        .contentShape(Rectangle())
        .sessionContextMenu(session: session, activityTitle: activityTitle,
            showEditActivity: false, onEdit: { beginEditing($0) }) {
            onReload?()
        }
    }

    // MARK: - Editing Helpers

    private func beginEditing(_ sessionId: Int64) {
        withAdaptiveAnimation(.easeInOut(duration: 0.2)) {
            editingSessionId = sessionId
        }
    }

    private func clearEditing() {
        // Force any active text editor to resign first responder before removing the form.
        // This triggers save-on-blur callbacks (e.g., saveNote) synchronously, ensuring
        // buffered changes are flushed before the form disappears.
        NSApp.keyWindow?.makeFirstResponder(nil)
        withAdaptiveAnimation(.easeInOut(duration: 0.2)) {
            editingSessionId = nil
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

    /// Live duration label for the active session, shared by both grouped and ungrouped row styles.
    @ViewBuilder
    private var activeDurationLabel: some View {
        if let preMidnight = activePreMidnightSeconds {
            HStack(spacing: 0) {
                Text(TimeFormatting.formatDuration(seconds: max(0, appState.timerElapsedSeconds - preMidnight), active: true))
                    .font(.durationDetail)
                    .foregroundStyle(theme.accent)
                    .contentTransition(.numericText())
                Text(" / \(TimeFormatting.formatDuration(seconds: appState.timerElapsedSeconds, active: true))")
                    .font(.durationDetail)
                    .foregroundStyle(theme.accent.opacity(0.5))
                    .contentTransition(.numericText())
            }
        } else {
            Text(TimeFormatting.formatDuration(seconds: appState.timerElapsedSeconds, active: true))
                .font(.durationDetail)
                .foregroundStyle(theme.accent)
                .contentTransition(.numericText())
        }
    }

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

    /// Alternating background for expanded sub-rows in grouped view.
    /// Uses a subtler opacity than the parent activity row stripes (0.08) to
    /// maintain visual hierarchy.
    private func subRowBackground(index: Int) -> Color {
        index.isMultiple(of: 2) ? Color.gray.opacity(0.04) : .clear
    }

    // MARK: - Session Display Helpers

    /// Format a start time respecting the current time reference mode.
    /// Single-day: annotate only if the time falls on a different day than the reference.
    /// Multi-day: always include the day-of-week.
    private func formatStartTime(_ date: Date) -> String {
        if let ref = timeReferenceDate {
            return TimeFormatting.formatTime(date, referenceDate: ref)
        }
        // Multi-day: always include day — use .distantPast so the day never matches.
        return TimeFormatting.formatTime(date, referenceDate: .distantPast)
    }

    /// Format an end time respecting the current time reference mode.
    /// Single-day: annotate only if the time falls on a different day than the reference.
    /// Multi-day: annotate only if the end falls on a different day than `sessionStart`.
    private func formatEndTime(_ date: Date, sessionStart: Date) -> String {
        if let ref = timeReferenceDate {
            return TimeFormatting.formatTime(date, referenceDate: ref)
        }
        // Multi-day: annotate only when end day differs from start day.
        return TimeFormatting.formatTime(date, referenceDate: sessionStart)
    }

    private func activityTimeRange(_ sessions: [Session], active: Session?) -> String? {
        var starts: [Date] = sessions.map(\.startedAt)
        let ends: [Date] = sessions.compactMap(\.endedAt)
        if let active {
            starts.append(active.startedAt)
        }
        guard let first = starts.min() else { return nil }
        if let last = ends.max() {
            return "\(formatStartTime(first)) \u{2013} \(formatEndTime(last, sessionStart: first))"
        }
        return formatStartTime(first)
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
        let start = formatStartTime(session.startedAt)
        guard let end = session.endedAt else { return start }
        return "\(start) \u{2013} \(formatEndTime(end, sessionStart: session.startedAt))"
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

    /// Muted tint for activity-level badges — grey that adapts to light/dark mode.
    private var mutedBadgeTint: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor.white.withAlphaComponent(0.6) : NSColor.black.withAlphaComponent(0.6)
        }))
    }

    /// The activity's own external ID badge — always visible, no animation.
    @ViewBuilder
    private func activityOwnBadge(activity: Activity) -> some View {
        if let extId = activity.externalId, !extId.isEmpty {
            TicketBadge(ticketId: extId, link: activity.link, font: .caption, tint: mutedBadgeTint)
        }
    }

    /// Deduplicated session-only external ID badges (excludes the activity's own externalId).
    @ViewBuilder
    private func sessionOnlyBadges(activity: Activity, sessions: [Session]) -> some View {
        let badges = collectSessionOnlyExternalIds(activity: activity, sessions: sessions)
        if !badges.isEmpty {
            HStack(spacing: Constants.spacingTight) {
                ForEach(badges, id: \.id) { badge in
                    TicketBadge(ticketId: badge.id, link: badge.link, font: .caption, tint: mutedBadgeTint)
                }
            }
        }
    }

    /// Collect deduplicated external IDs from sessions, excluding the activity's own externalId.
    private func collectSessionOnlyExternalIds(activity: Activity, sessions: [Session]) -> [(id: String, link: String?)] {
        let activityExtId = activity.externalId ?? ""
        var seen = Set<String>()
        var result: [(id: String, link: String?)] = []

        for session in sessions {
            if let ticketId = session.ticketId, !ticketId.isEmpty,
               ticketId != activityExtId, seen.insert(ticketId).inserted {
                result.append((id: ticketId, link: session.link))
            }
        }

        return result
    }

    /// Note indicator and ticket badge shown between session details and the duration label.
    /// When `activityExternalId` is provided, the session badge is hidden if it matches the activity's own ID.
    @ViewBuilder
    private func sessionMetadataBadges(_ session: Session, activityExternalId: String? = nil) -> some View {
        if session.note != nil {
            Image(systemName: "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Has note")
                .help(session.note ?? "")
                .onTapGesture {
                    guard let id = session.id, editingSessionId != id else { return }
                    beginEditing(id)
                }
        }

        if let ticketId = session.ticketId, ticketId != activityExternalId {
            TicketBadge(ticketId: ticketId, link: session.link, font: .caption, tint: mutedBadgeTint)
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
            let portions = try await appState.sessionDayPortions(
                sessionIds: [sessionId], date: Date()
            )
            let todayFromSegments = portions[sessionId] ?? 0
            activePreMidnightSeconds = max(0, appState.timerElapsedSeconds - todayFromSegments)
        } catch {
            activePreMidnightSeconds = nil
        }
    }
}
