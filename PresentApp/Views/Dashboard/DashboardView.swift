import SwiftUI
import PresentCore

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var quickRestartSuggestions: [(Session, Activity)] = []
    @State private var contentWidth: CGFloat = 600
    /// Tracks the current date for greeting/date text; updated at period boundaries.
    @State private var greetingDate = Date()

    /// Shared color mapping so today timeline and weekly chart use the same color per activity.
    ///
    /// On-page activities get first pick from the palette to minimize overlap for
    /// visible data. Remaining non-archived activities are appended so a
    /// just-started session always has a color slot — even before the weekly
    /// summary refreshes (which previously caused a Swift Charts crash).
    private var activityColorMap: [String: Color] {
        let palette = ThemeManager.chartColors(for: theme.activePalette)

        // 1. Activities currently visible on the dashboard get priority colors.
        var onPage = Set<String>()
        for summary in appState.todayActivities {
            onPage.insert(summary.activity.title)
        }
        if let weekly = appState.weeklySummary {
            for summary in weekly.activities {
                onPage.insert(summary.activity.title)
            }
        }
        // Include active session's activity so cross-midnight sessions get a chart color.
        // Skip system activities (Break) — they don't need chart representation.
        if let current = appState.currentActivity, !current.isSystem {
            onPage.insert(current.title)
        }
        let sortedOnPage = onPage.sorted()

        // 2. All other non-archived, non-system activities fill remaining palette slots.
        let remaining = appState.allActivities
            .filter { !$0.isArchived && !$0.isSystem && !onPage.contains($0.title) }
            .map(\.title)
            .sorted()

        let allTitles = sortedOnPage + remaining
        var map: [String: Color] = [:]
        for (index, title) in allTitles.enumerated() {
            map[title] = palette[index % palette.count]
        }
        return map
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Greeting header with timer or quick restarts
                dashboardHeader

                // Weekly chart
                if let weekly = appState.weeklySummary, !weekly.activities.isEmpty || hasActiveTodaySession {
                    WeeklyChartCard(
                        activityColorMap: activityColorMap,
                        weekly: weekly,
                        hasActiveTodaySession: hasActiveTodaySession,
                        todayPortionSeconds: todayPortionSeconds,
                        currentActivity: appState.currentActivity,
                        reduceMotion: reduceMotion
                    )
                }

                // Activity breakdown
                activityBreakdownCard
            }
            .padding(Constants.spacingPage)
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { contentWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newValue in contentWidth = newValue }
            })
        }
        .navigationTitle("Dashboard")
        .task { await refreshGreetingAtBoundary() }
        .task(id: appState.isSessionActive) {
            if appState.isSessionActive {
                quickRestartSuggestions = []
            } else {
                await loadQuickRestarts()
            }
        }
    }

    // MARK: - Today stats (including active session)

    /// Active session always contributes to today — even if it started yesterday (cross-midnight).
    private var hasActiveTodaySession: Bool {
        appState.isSessionActive && appState.currentSession != nil
    }

    /// For cross-midnight sessions, only count the portion since midnight.
    private var todayPortionSeconds: Int {
        guard hasActiveTodaySession, let session = appState.currentSession else { return 0 }
        if Calendar.current.isDateInToday(session.startedAt) {
            return appState.timerElapsedSeconds
        }
        let secondsSinceMidnight = Int(Date().timeIntervalSince(Calendar.current.startOfDay(for: Date())))
        return min(appState.timerElapsedSeconds, secondsSinceMidnight)
    }

    private var displayTotalSeconds: Int {
        appState.todayTotalSeconds + todayPortionSeconds
    }

    private var displaySessionCount: Int {
        appState.todaySessionCount + (hasActiveTodaySession ? 1 : 0)
    }

    private var displayActivityCount: Int {
        var count = appState.todayActivities.count
        if hasActiveTodaySession,
           let activity = appState.currentActivity,
           !appState.todayActivities.contains(where: { $0.activity.id == activity.id }) {
            count += 1
        }
        return count
    }

    // MARK: - Greeting helpers

    /// Greeting periods defined as (start hour, phrase). Ordered chronologically.
    /// Both `greeting` and `refreshGreetingAtBoundary` derive from this.
    private static let greetingPeriods: [(hour: Int, phrase: String)] = [
        (0, "Good morning"),
        (12, "Good afternoon"),
        (18, "Good evening"),
    ]

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: greetingDate)
        // Walk backwards to find the last period whose start hour we've passed.
        return Self.greetingPeriods.last { hour >= $0.hour }?.phrase ?? Self.greetingPeriods[0].phrase
    }

    private var dateText: String {
        let f = DateFormatter()
        f.dateStyle = .full
        return f.string(from: greetingDate)
    }

    /// Sleeps until the next greeting boundary and updates `greetingDate`.
    private func refreshGreetingAtBoundary() async {
        let boundaryHours = Self.greetingPeriods.map(\.hour)

        while !Task.isCancelled {
            let calendar = Calendar.current
            let now = Date()
            let hour = calendar.component(.hour, from: now)

            // Next boundary is the first hour > current, or wrap to first boundary (midnight/next day).
            let nextHour = boundaryHours.first { $0 > hour } ?? boundaryHours[0]

            var target = calendar.date(bySettingHour: nextHour, minute: 0, second: 0, of: now) ?? now
            if target <= now {
                target = calendar.date(byAdding: .day, value: 1, to: target) ?? now
            }

            let delay = target.timeIntervalSinceNow
            guard delay > 0 else { break }

            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { break }
            greetingDate = Date()
        }
    }

    // MARK: - Quick restart loader

    private func loadQuickRestarts() async {
        let lookback = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        guard let sessions = try? await appState.service.listSessions(
            from: lookback, to: Date(), type: nil, activityId: nil, includeArchived: false
        ) else { return }
        var seen = Set<String>()
        var unique: [(Session, Activity)] = []
        for (session, activity) in sessions {
            let key = "\(session.activityId)-\(session.sessionType.rawValue)"
            if seen.insert(key).inserted {
                unique.append((session, activity))
                if unique.count == 3 { break }
            }
        }
        quickRestartSuggestions = unique
    }

    // MARK: - Dashboard Header

    private var dashboardHeader: some View {
        VStack(spacing: Constants.spacingCard) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greeting)
                        .font(.dashboardGreeting)
                        .tracking(1.5)
                    Text(dateText)
                        .font(.periodHeader)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: contentWidth * 0.35, alignment: .leading)

                Spacer(minLength: 0)

                if appState.isSessionActive {
                    activeTimerPanel
                        .frame(minWidth: 320, maxWidth: max(320, contentWidth * 0.3))
                } else if !quickRestartSuggestions.isEmpty {
                    quickRestartPanel
                        .frame(minWidth: 320, maxWidth: max(320, contentWidth * 0.3))
                }
            }
            .overlay {
                // Logo bloom fills the space between greeting and panel
                LogoBloomView()
                    .allowsHitTesting(false)
            }

            GroupBox {
                Text("Today at a Glance")
                    .font(.cardTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Constants.spacingCard)
                    .padding(.top, Constants.spacingCard)
                    .padding(.bottom, Constants.spacingCard)

                HStack(alignment: .center, spacing: Constants.spacingPage * 2) {
                    HStack(spacing: 40) {
                        StatItem(
                            title: "Total Time",
                            value: TimeFormatting.formatDuration(seconds: displayTotalSeconds),
                            icon: "clock"
                        )

                        StatItem(
                            title: "Sessions",
                            value: "\(displaySessionCount)",
                            icon: "number"
                        )

                        StatItem(
                            title: "Activities",
                            value: "\(displayActivityCount)",
                            icon: "tray"
                        )
                    }

                    DayTimelineView(activityColorMap: activityColorMap)
                        .frame(maxWidth: .infinity)
                }
                .padding(Constants.spacingCard)
            }
        }
    }

    // MARK: - Active Timer Panel

    private var activeTimerPanel: some View {
        GroupBox {
            VStack(spacing: 12) {
                if let activity = appState.currentActivity, let session = appState.currentSession {
                    VStack(spacing: 4) {
                        Text(activity.title)
                            .font(.headline)
                            .lineLimit(1)

                        Text(SessionTypeConfig.config(for: session.sessionType).displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(appState.formattedTimerValue)
                    .font(.timerDisplay)
                    .contentTransition(.numericText())

                SessionControls()
            }
            .padding(Constants.spacingCard)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Quick Restart Panel

    private var quickRestartPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Continue Recent Activities")
                .font(.title3.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, Constants.spacingCard)
                .padding(.bottom, Constants.spacingCompact)

            ForEach(Array(quickRestartSuggestions.enumerated()), id: \.offset) { _, pair in
                let (session, activity) = pair
                QuickStartRow(
                    activity: activity,
                    icon: "arrow.counterclockwise.circle.fill",
                    subtitle: sessionSubtitle(session),
                    onTap: {
                        Task { await appState.startSession(activityId: session.activityId, type: session.sessionType, timerMinutes: session.timerLengthMinutes, breakMinutes: session.breakMinutes) }
                    },
                    onEdit: {
                        if let id = activity.id {
                            appState.navigate(to: .showActivity(id))
                        }
                    }
                )
            }
        }
    }

    private func sessionSubtitle(_ session: Session) -> String {
        let typeName = SessionTypeConfig.config(for: session.sessionType).displayName
        switch session.sessionType {
        case .rhythm:
            if let focus = session.timerLengthMinutes, let brk = session.breakMinutes {
                return "\(typeName) · \(RhythmOption(focusMinutes: focus, breakMinutes: brk).displayLabel)"
            }
            return typeName
        case .timebound:
            if let minutes = session.timerLengthMinutes {
                return "\(typeName) (\(minutes)m)"
            }
            return typeName
        default:
            return typeName
        }
    }

    // MARK: - Activity Breakdown

    private var activityBreakdownCard: some View {
        ActivityBreakdownCard(activityColorMap: activityColorMap)
    }
}
