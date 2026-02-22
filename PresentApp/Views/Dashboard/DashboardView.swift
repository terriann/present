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

    /// Shared color mapping so today timeline and weekly chart use the same color per activity.
    private var activityColorMap: [String: Color] {
        let palette = ThemeManager.chartColors(for: theme.activePalette)
        var titles = Set<String>()
        for summary in appState.todayActivities {
            titles.insert(summary.activity.title)
        }
        if let weekly = appState.weeklySummary {
            for summary in weekly.activities {
                titles.insert(summary.activity.title)
            }
        }
        let sorted = titles.sorted()
        var map: [String: Color] = [:]
        for (index, title) in sorted.enumerated() {
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
        .alert(appState.isLongBreak ? "Time for a Long Break!" : "Take a Short Break",
               isPresented: Bindable(appState).showBreakSuggestion) {
            Button("OK") { appState.dismissBreakSuggestion() }
        } message: {
            Text("You've earned a \(appState.suggestedBreakMinutes)-minute break. Step away and recharge.")
        }
        .task(id: appState.isSessionActive) {
            if appState.isSessionActive {
                quickRestartSuggestions = []
            } else {
                await loadQuickRestarts()
            }
        }
    }

    // MARK: - Today stats (including active session)

    private var hasActiveTodaySession: Bool {
        guard appState.isSessionActive, let session = appState.currentSession else { return false }
        return Calendar.current.isDateInToday(session.startedAt)
    }

    private var displayTotalSeconds: Int {
        appState.todayTotalSeconds + (hasActiveTodaySession ? appState.timerElapsedSeconds : 0)
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

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var dateText: String {
        let f = DateFormatter()
        f.dateStyle = .full
        return f.string(from: Date())
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
                Text("Today")
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
                return "\(typeName) · \(focus)m / \(brk)m"
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

        return ChartCard(title: "This Week", subtitle: weekRangeTitle) {
            weeklyBarChart(entries: entries, domain: domain, activities: weekly.activities, tooltipLabels: tooltipLabels)
        }
    }

    private func weeklyBarChart(entries: [DashboardBarEntry], domain: [String], activities: [ActivitySummary], tooltipLabels: [String: String]) -> some View {
        let colorDomain = activities.map(\.activity.title).sorted()
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
                .opacity(hoveredBarLabel == nil || hoveredBarLabel == entry.label ? 1.0 : 0.4)
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
        weekly.dailyBreakdown.flatMap { daily in
            daily.activities.map { summary in
                DashboardBarEntry(
                    label: dayLabel(daily.date),
                    activity: summary.activity.title,
                    value: Double(summary.totalSeconds) / 3600.0
                )
            }
        }
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
        if value < 0.1 {
            return String(format: "%.0fm", value * 60)
        }
        return String(format: "%.1fh", value)
    }

    // MARK: - Activity Breakdown

    private var activityBreakdownCard: some View {
        ActivityBreakdownCard()
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

    private let barHeight: CGFloat = 48
    private let axisHours = stride(from: 0, through: 24, by: 3).map { $0 }
    private var startOfDay: Date { Calendar.current.startOfDay(for: Date()) }
    private let secondsInDay: Double = 24 * 60 * 60

    private var allSessions: [(Session, Activity)] {
        var result = completedSessions
        if let current = appState.currentSession,
           let activity = appState.currentActivity,
           Calendar.current.isDateInToday(current.startedAt),
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

                        RoundedRectangle(cornerRadius: 5)
                            .fill(color.opacity(isActive ? 1.0 : 0.75))
                            .frame(width: w, height: barHeight)
                            .offset(x: x)
                            .opacity(dimmed ? 0.2 : 1.0)
                    }

                    // Current time indicator
                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 2, height: barHeight + 6)
                        .offset(x: nowPos(geo.size.width))

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
        let offset = session.startedAt.timeIntervalSince(startOfDay)
        return CGFloat(offset / secondsInDay) * width
    }

    private func blockWidth(_ session: Session, _ width: CGFloat) -> CGFloat {
        let end: Date = session.endedAt ?? session.startedAt.addingTimeInterval(
            Double(appState.timerElapsedSeconds)
        )
        let duration = max(1, end.timeIntervalSince(session.startedAt))
        return max(6, CGFloat(duration / secondsInDay) * width)
    }

    private func nowPos(_ width: CGFloat) -> CGFloat {
        CGFloat(Date().timeIntervalSince(startOfDay) / secondsInDay) * width
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
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var expandedActivities: Set<Int64> = []
    @State private var todaySessions: [Int64: [Session]] = [:]

    var body: some View {
        ChartCard(title: "Activity Breakdown") {
            if appState.todayActivities.isEmpty {
                ContentUnavailableView(
                    "No Activities",
                    systemImage: "list.bullet",
                    description: Text("No activities recorded for this period.")
                )
                .emptyStateStyle()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(appState.todayActivities.enumerated()), id: \.element.activity.id) { index, summary in
                        let activityId = summary.activity.id ?? -1
                        let isExpanded = expandedActivities.contains(activityId)
                        let sessions = todaySessions[activityId]
                        let activeSession: Session? = appState.currentSession?.activityId == activityId ? appState.currentSession : nil
                        let totalCount = summary.sessionCount + (activeSession != nil ? 1 : 0)

                        VStack(spacing: 0) {
                            HStack {
                                if totalCount > 1 {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .hidden()
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(summary.activity.title)
                                        .font(.body)
                                        .lineLimit(1)

                                    HStack(spacing: 4) {
                                        Text("\(totalCount) \(totalCount == 1 ? "session" : "sessions")")
                                        if let range = activityTimeRange(sessions, active: activeSession) {
                                            Text("·")
                                            Text(range)
                                        }
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(TimeFormatting.formatDuration(seconds: summary.totalSeconds))
                                    .font(.durationValue)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, Constants.spacingCompact)
                            .padding(.horizontal, Constants.spacingCard)
                            .background(index.isMultiple(of: 2) ? Color.clear : Color.gray.opacity(0.08))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard totalCount > 1 else { return }
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
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(SessionTypeConfig.config(for: active.sessionType).displayName)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                            Text(TimeFormatting.formatTime(active.startedAt))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(appState.formattedTimerValue)
                                            .font(.durationDetail)
                                            .foregroundStyle(theme.accent)
                                            .contentTransition(.numericText())
                                        SpinningClockIcon(isRunning: activeSession?.state == .running)
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
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(SessionTypeConfig.config(for: session.sessionType).displayName)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)

                                            Text(sessionTimeRange(session))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        if let duration = session.durationSeconds {
                                            Text(TimeFormatting.formatDuration(seconds: duration))
                                                .font(.durationDetail)
                                                .foregroundStyle(.secondary)
                                        }

                                        stateIcon(for: session)
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
        .task(id: appState.todayActivities.map { $0.activity.id }) {
            for summary in appState.todayActivities {
                if let id = summary.activity.id {
                    loadSessionsForActivity(id)
                }
            }
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
        if let last = ends.max() {
            return "\(TimeFormatting.formatTime(first)) – \(TimeFormatting.formatTime(last))"
        }
        // Only active session (no completed end times yet)
        return TimeFormatting.formatTime(first)
    }

    private func sessionTimeRange(_ session: Session) -> String {
        let start = TimeFormatting.formatTime(session.startedAt)
        guard let end = session.endedAt else { return start }
        return "\(start) – \(TimeFormatting.formatTime(end))"
    }

    @ViewBuilder
    private func stateIcon(for session: Session) -> some View {
        switch (session.state, session.sessionType) {
        case (.cancelled, _):
            Image(systemName: "xmark.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case (.completed, .work):
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(theme.success)

        case (.completed, .rhythm), (.completed, .timebound):
            let fullyElapsed = session.timerLengthMinutes
                .flatMap { target in session.durationSeconds.map { $0 >= target * 60 } } ?? false
            if fullyElapsed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(theme.success)
            } else {
                Image(systemName: "xmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        default:
            EmptyView()
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
                todaySessions[activityId] = sessions.map(\.0).sorted {
                    ($0.endedAt ?? .distantFuture) > ($1.endedAt ?? .distantFuture)
                }
            } catch {
                // Fail silently
            }
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
}
