import SwiftUI
import Charts
import PresentCore

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredBarLabel: String?
    @State private var hoveredBarActivity: String?
    @State private var barHoverLocation: CGPoint = .zero
    @State private var quickRestartSuggestions: [(Session, Activity)] = []
    @State private var contentWidth: CGFloat = 600
    /// Drives the gentle pulse on the active session's bar segment in the weekly chart.
    @State private var activePulseOpacity: Double = 1.0
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
                    weeklyChartCard(weekly)
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
                // Pulse the active bar segment in the weekly chart (matches today timeline timing)
                guard !reduceMotion else {
                    activePulseOpacity = 1.0
                    return
                }
                let midpoint = (Constants.activePulseHigh + Constants.activePulseLow) / 2
                let amplitude = (Constants.activePulseHigh - Constants.activePulseLow) / 2
                let period = Constants.activePulseDuration * 2 + Constants.activePulseDelay
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(50))
                    let t = Date().timeIntervalSinceReferenceDate
                    activePulseOpacity = midpoint + amplitude * sin(t * 2 * .pi / period)
                }
            } else {
                activePulseOpacity = 1.0
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

    // MARK: - Weekly Chart

    private var weekRangeTitle: String {
        var calendar = Calendar.current
        calendar.firstWeekday = appState.weekStartDay
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return "This Week" }
        let start = interval.start
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        return TimeFormatting.formatWeekRange(start: start, end: end)
    }

    private func weeklyChartCard(_ weekly: WeeklySummary) -> some View {
        let entries = weeklyBarEntries(weekly)
        let domain = weekdayLabels(weekly)
        let tooltipLabels = weeklyTooltipLabels(weekStartDay: appState.weekStartDay, referenceDate: Date())

        // Build color domain/range for the legend (same logic as weeklyBarChart)
        var allTitles = Set(weekly.activities.map(\.activity.title))
        for entry in entries { allTitles.insert(entry.activity) }
        let colorDomain = allTitles.sorted()
        let colorRange = colorDomain.map { activityColorMap[$0] ?? .secondary }

        return ChartCard(title: "Your Week", subtitle: weekRangeTitle) {
            weeklyBarChart(entries: entries, domain: domain, activities: weekly.activities, tooltipLabels: tooltipLabels)
            weeklyBarChartLegend(colorDomain: colorDomain, colorRange: colorRange)
        }
    }

    private func weeklyBarChart(entries: [DashboardBarEntry], domain: [String], activities: [ActivitySummary], tooltipLabels: [String: String]) -> some View {
        // Include activity titles from entries too — a just-started session may
        // inject a bar entry before the weekly summary refreshes.
        var allTitles = Set(activities.map(\.activity.title))
        for entry in entries {
            allTitles.insert(entry.activity)
        }
        let colorDomain = allTitles.sorted()
        let colorRange = colorDomain.map { activityColorMap[$0] ?? .secondary }

        // Compute y-axis domain
        var labelTotals: [String: Double] = [:]
        for entry in entries {
            labelTotals[entry.label, default: 0] += entry.value
        }
        let peak = labelTotals.values.max() ?? 0
        let rounded = max(1, ceil(peak / 1) * 1)
        let yDomain = 0...min(rounded + 1, 25)

        let weekendDays = weekendLabels(
            period: .weekly,
            weekStartDay: appState.weekStartDay,
            selectedDate: Date()
        )

        return Chart {
            ForEach(Array(weekendDays), id: \.self) { label in
                RectangleMark(x: .value("Day", label))
                    .foregroundStyle(Color.gray.opacity(0.08))
                    .zIndex(-1)
            }

            ForEach(entries, id: \.id) { entry in
                BarMark(
                    x: .value("Day", entry.label),
                    y: .value("Hours", entry.value)
                )
                .foregroundStyle(by: .value("Activity", entry.activity))
                .opacity(weeklyBarEntryOpacity(entry: entry))
            }
        }
        .chartForegroundStyleScale(domain: colorDomain, range: colorRange)
        .chartXScale(domain: domain)
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))h")
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]

                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let relativeX = location.x - frame.origin.x
                                if let label: String = proxy.value(atX: relativeX),
                                   entries.contains(where: { $0.label == label }) {
                                    hoveredBarLabel = label
                                    barHoverLocation = location
                                } else {
                                    hoveredBarLabel = nil
                                }
                            case .ended:
                                hoveredBarLabel = nil
                            }
                        }

                    if let label = hoveredBarLabel {
                        let pos = tooltipPosition(cursor: barHoverLocation, containerSize: geometry.size)
                        weeklyBarTooltip(for: label, entries: entries, activities: activities, tooltipLabels: tooltipLabels)
                            .fixedSize()
                            .frame(maxWidth: 180, alignment: .leading)
                            .position(x: pos.x, y: pos.y)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: 250)
        .padding(Constants.spacingCard)
    }

    private func weeklyBarTooltip(for label: String, entries: [DashboardBarEntry], activities: [ActivitySummary], tooltipLabels: [String: String]) -> some View {
        let matching = entries.filter { $0.label == label }
        let bucketTotal = matching.reduce(0.0) { $0 + $1.value }

        return ChartTooltip {
            Text(tooltipLabels[label] ?? label)
                .font(.dataLabel)

            ForEach(matching, id: \.id) { entry in
                HStack(spacing: 6) {
                    let color = activityColorMap[entry.activity] ?? .secondary
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                    Text(entry.activity)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(formatHours(entry.value))
                        .font(.dataValue)
                }
            }

            if matching.count > 1 {
                Divider()
                HStack {
                    Text("Total")
                        .font(.dataLabel)
                    Spacer()
                    Text(formatHours(bucketTotal))
                        .font(.dataBoldValue)
                }
            }
        }
    }

    private func weeklyBarEntryOpacity(entry: DashboardBarEntry) -> Double {
        // Legend hover takes priority — isolate a single activity across all days
        if let activity = hoveredBarActivity {
            return entry.activity == activity ? 1.0 : 0.15
        }
        // Tooltip hover — highlight a single day
        if let label = hoveredBarLabel {
            return entry.label == label ? 1.0 : 0.4
        }
        // Active session segment pulses when no hover interaction is active
        if entry.isActive { return activePulseOpacity }
        return 1.0
    }

    private func weeklyBarChartLegend(colorDomain: [String], colorRange: [Color]) -> some View {
        let items = zip(colorDomain, colorRange).map { (label: $0, color: $1) }
        return HoverableChartLegend(
            items: items,
            hoveredLabel: $hoveredBarActivity
        )
        .padding(.horizontal, Constants.spacingCard)
        .padding(.bottom, Constants.spacingCard)
    }

    // MARK: - Weekly Chart Helpers

    private func weeklyBarEntries(_ weekly: WeeklySummary) -> [DashboardBarEntry] {
        var entries = weekly.dailyBreakdown.flatMap { daily in
            daily.activities.map { summary in
                DashboardBarEntry(
                    label: dayLabel(daily.date),
                    activity: summary.activity.title,
                    value: Double(summary.totalSeconds) / 3600.0
                )
            }
        }

        // Inject active session's today portion into the chart.
        // Skip system activities (e.g., Break) — they aren't in the weekly
        // summary's activity list yet, so the chart's colorDomain won't
        // include them, causing a Swift Charts crash.
        if hasActiveTodaySession, let activity = appState.currentActivity, !activity.isSystem {
            let todayLabel = dayLabel(Date())
            let activeHours = Double(todayPortionSeconds) / 3600.0
            if let index = entries.firstIndex(where: { $0.label == todayLabel && $0.activity == activity.title }) {
                let existing = entries[index]
                entries[index] = DashboardBarEntry(
                    label: existing.label, activity: existing.activity,
                    value: existing.value + activeHours, isActive: true
                )
            } else {
                entries.append(DashboardBarEntry(
                    label: todayLabel, activity: activity.title,
                    value: activeHours, isActive: true
                ))
            }
        }

        return entries
    }

    private func weekdayLabels(_ weekly: WeeklySummary) -> [String] {
        var calendar = Calendar.current
        calendar.firstWeekday = appState.weekStartDay
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        guard let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return [] }
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return formatter.string(from: date)
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func formatHours(_ value: Double) -> String {
        TimeFormatting.formatDuration(seconds: Int((value * 3600).rounded()))
    }

    // MARK: - Activity Breakdown

    private var activityBreakdownCard: some View {
        ActivityBreakdownCard(activityColorMap: activityColorMap)
    }
}

// MARK: - Supporting Types

private struct DashboardBarEntry: Identifiable {
    var id: String { "\(label)-\(activity)" }
    let label: String
    let activity: String
    let value: Double
    var isActive: Bool = false
}
