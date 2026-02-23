import SwiftUI
import Charts
import PresentCore

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var hoveredBarLabel: String?
    @State private var barHoverLocation: CGPoint = .zero
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
                if let weekly = appState.weeklySummary, !weekly.activities.isEmpty {
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
                        appState.navigateToActivityId = activity.id
                        appState.selectedSidebarItem = .activities
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

        return ChartCard(title: "Your Week", subtitle: weekRangeTitle) {
            weeklyBarChart(entries: entries, domain: domain, activities: weekly.activities, tooltipLabels: tooltipLabels)
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
                .opacity(entry.isActive
                    ? 0.6
                    : (hoveredBarLabel == nil || hoveredBarLabel == entry.label ? 1.0 : 0.4))
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
        .chartLegend(position: .bottom, spacing: 12)
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

// MARK: - Day Timeline View

private struct DayTimelineView: View {
    let activityColorMap: [String: Color]
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var completedSessions: [(Session, Activity)] = []
    @State private var hoveredActivityTitle: String? = nil
    @State private var hoveredSessionPair: (Session, Activity)?
    @State private var hoverLocation: CGPoint = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barHeight: CGFloat = 48
    private let axisHours = stride(from: 0, through: 24, by: 3).map { $0 }
    private var startOfDay: Date { Calendar.current.startOfDay(for: Date()) }
    private let secondsInDay: Double = 24 * 60 * 60

    private var allSessions: [(Session, Activity)] {
        var result = completedSessions
        // Include active session regardless of start date (handles cross-midnight)
        if let current = appState.currentSession,
           let activity = appState.currentActivity,
           !result.contains(where: { $0.0.id == current.id }) {
            result.insert((current, activity), at: 0)
        }
        return result
    }

    private var legendItems: [(label: String, color: Color)] {
        var seen = Set<Int64>()
        var items: [(label: String, color: Color)] = []
        for (_, activity) in allSessions {
            guard let id = activity.id, seen.insert(id).inserted else { continue }
            items.append((label: activity.title, color: activityColor(activity)))
        }
        return items.sorted { $0.label < $1.label }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.spacingCompact) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track background (extended past tick marks so corners don't clip them)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.12))
                        .frame(width: geo.size.width + 16, height: barHeight)
                        .offset(x: -8)

                    // Session blocks
                    ForEach(allSessions, id: \.0.id) { session, activity in
                        let x = xPos(session, geo.size.width)
                        let w = blockWidth(session, geo.size.width)
                        let color = activityColor(activity)
                        let isActive = session.id == appState.currentSession?.id
                        let dimmed = hoveredActivityTitle != nil && hoveredActivityTitle != activity.title

                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(color.opacity(isActive ? 1.0 : 0.75))
                            .frame(width: w, height: barHeight)
                            .offset(x: x)
                            .phaseAnimator(
                                isActive && !reduceMotion ? [0.75, 0.3] : [isActive ? 0.75 : 1.0]
                            ) { content, phase in
                                content.opacity(dimmed ? 0.2 : phase)
                            } animation: { phase in
                                phase == 0.3
                                    ? .easeInOut(duration: 3.0).delay(1.0)
                                    : .easeInOut(duration: 3.0)
                            }
                    }

                    // X-axis tick marks
                    ForEach(axisHours, id: \.self) { hour in
                        Rectangle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 1, height: barHeight)
                            .offset(x: CGFloat(hour) / 24.0 * geo.size.width)
                    }
                }
                .frame(height: barHeight)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        hoverLocation = point
                        let match = sessionAt(x: point.x, width: geo.size.width)
                        hoveredSessionPair = match
                        hoveredActivityTitle = match?.1.title
                    case .ended:
                        hoveredSessionPair = nil
                        hoveredActivityTitle = nil
                    }
                }
                .overlay {
                    if let (session, activity) = hoveredSessionPair {
                        let midX = xPos(session, geo.size.width)
                            + blockWidth(session, geo.size.width) / 2
                        let clampedX = min(max(90, midX), geo.size.width - 90)
                        timelineTooltip(session: session, activity: activity)
                            .fixedSize()
                            .position(x: clampedX, y: -36)
                    }
                }

                // X-axis labels
                ZStack(alignment: .topLeading) {
                    ForEach(axisHours, id: \.self) { hour in
                        if hour == 24 {
                            Text(axisLabel(hour))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        } else {
                            Text(axisLabel(hour))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .offset(x: max(0, CGFloat(hour) / 24.0 * geo.size.width - 10))
                        }
                    }
                }
                .frame(height: 14)
                .offset(y: barHeight + 2)
            }
            .frame(height: barHeight + 16)

            // Legend
            if !legendItems.isEmpty {
                HoverableChartLegend(items: legendItems, hoveredLabel: $hoveredActivityTitle)
            }
        }
        .task(id: appState.todayActivities.map(\.activity.id)) {
            await loadSessions()
        }
    }

    // MARK: - Helpers

    private func xPos(_ session: Session, _ width: CGFloat) -> CGFloat {
        // Clamp to start of day so cross-midnight sessions begin at x=0
        let effectiveStart = max(session.startedAt, startOfDay)
        let offset = effectiveStart.timeIntervalSince(startOfDay)
        return CGFloat(offset / secondsInDay) * width
    }

    private func blockWidth(_ session: Session, _ width: CGFloat) -> CGFloat {
        let effectiveStart = max(session.startedAt, startOfDay)
        let end: Date = session.endedAt ?? session.startedAt.addingTimeInterval(
            Double(appState.timerElapsedSeconds)
        )
        let duration = max(1, end.timeIntervalSince(effectiveStart))
        return max(6, CGFloat(duration / secondsInDay) * width)
    }

    private func activityColor(_ activity: Activity) -> Color {
        activityColorMap[activity.title] ?? .secondary
    }

    private func axisLabel(_ hour: Int) -> String {
        switch hour {
        case 0, 24: return "12am"
        case 12: return "12pm"
        default: return hour < 12 ? "\(hour)am" : "\(hour - 12)pm"
        }
    }

    private func sessionAt(x: CGFloat, width: CGFloat) -> (Session, Activity)? {
        for (session, activity) in allSessions.reversed() {
            let sx = xPos(session, width)
            let sw = blockWidth(session, width)
            if x >= sx && x <= sx + sw {
                return (session, activity)
            }
        }
        return nil
    }

    @ViewBuilder
    private func timelineTooltip(session: Session, activity: Activity) -> some View {
        ChartTooltip {
            Text(activity.title)
                .font(.caption)
                .fontWeight(.semibold)

            Text(SessionTypeConfig.config(for: session.sessionType).displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(tooltipDuration(session))
                .font(.caption)
                .monospacedDigit()

            Text(tooltipTimeRange(session))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func tooltipDuration(_ session: Session) -> String {
        if let dur = session.durationSeconds {
            return TimeFormatting.formatDuration(seconds: dur)
        }
        return TimeFormatting.formatDuration(seconds: appState.timerElapsedSeconds)
    }

    private func tooltipTimeRange(_ session: Session) -> String {
        let start = TimeFormatting.formatTime(session.startedAt)
        if let end = session.endedAt {
            return "\(start) – \(TimeFormatting.formatTime(end))"
        }
        return "\(start) – now"
    }

    private func loadSessions() async {
        guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        guard let result = try? await appState.service.listSessions(
            from: startOfDay, to: endOfDay, type: nil, activityId: nil, includeArchived: false
        ) else { return }
        completedSessions = result
    }
}

// MARK: - Activity Breakdown Card

private struct ActivityBreakdownCard: View {
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
                                            Text("·")
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
            return "\(TimeFormatting.formatTime(first, referenceDate: today)) – \(TimeFormatting.formatTime(last, referenceDate: today))"
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
                return "\(base) · \(minutes)m"
            }
        case .rhythm:
            if let work = session.timerLengthMinutes, let brk = session.breakMinutes {
                return "\(base) · \(RhythmOption(focusMinutes: work, breakMinutes: brk).displayLabel)"
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
        return "\(start) – \(TimeFormatting.formatTime(end, referenceDate: today))"
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

// MARK: - Spinning Clock Icon

private struct SpinningClockIcon: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isRunning: Bool
    @State private var degrees: Double = 0

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .font(.subheadline)
            .foregroundStyle(theme.accent)
            .rotationEffect(.degrees(degrees))
            .onAppear {
                guard isRunning, !reduceMotion else { return }
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    degrees = 360
                }
            }
            .onChange(of: isRunning) { _, running in
                if running, !reduceMotion {
                    withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                        degrees = 360
                    }
                } else {
                    withAnimation(.default) { degrees = 0 }
                }
            }
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
