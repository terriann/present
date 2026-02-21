import SwiftUI
import Charts
import PresentCore

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var hoveredBarLabel: String?
    @State private var barHoverLocation: CGPoint = .zero
    @State private var quickRestartSuggestions: [(Session, Activity)] = []

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

                Spacer()

                if appState.isSessionActive {
                    activeTimerPanel
                } else if !quickRestartSuggestions.isEmpty {
                    quickRestartPanel
                }
            }

            GroupBox {
                Text("Today")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Constants.spacingCard)
                    .padding(.top, Constants.spacingCard)
                    .padding(.bottom, Constants.spacingCard)

                HStack(spacing: 40) {
                    StatItem(
                        title: "Total Time",
                        value: TimeFormatting.formatDuration(seconds: appState.todayTotalSeconds),
                        icon: "clock"
                    )

                    StatItem(
                        title: "Sessions",
                        value: "\(appState.todaySessionCount)",
                        icon: "number"
                    )

                    StatItem(
                        title: "Activities",
                        value: "\(appState.todayActivities.count)",
                        icon: "tray"
                    )

                    Spacer()
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
                    .font(.system(size: 36, weight: .light, design: .monospaced))
                    .contentTransition(.numericText())

                SessionControls()
            }
            .padding(Constants.spacingCard)
            .frame(width: 320)
        }
        .frame(width: 320)
    }

    // MARK: - Quick Restart Panel

    private var quickRestartPanel: some View {
        VStack(spacing: 0) {
            ForEach(Array(quickRestartSuggestions.enumerated()), id: \.offset) { index, pair in
                let (session, activity) = pair
                Button {
                    Task { await appState.startSession(activityId: session.activityId, type: session.sessionType) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.title)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(SessionTypeConfig.config(for: session.sessionType).displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "play.circle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, Constants.spacingCompact)
                    .padding(.horizontal, Constants.spacingCard)
                    .background(index.isMultiple(of: 2) ? Color.clear : Color.gray.opacity(0.08))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: 200)
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
        let colorDomain = activities.map(\.activity.title)
        let palette = ThemeManager.chartColors(for: theme.activePalette)
        let colorRange = activities.indices.map { palette[$0 % palette.count] }

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
        let palette = ThemeManager.chartColors(for: theme.activePalette)

        return ChartTooltip {
            Text(tooltipLabels[label] ?? label)
                .font(.caption.bold())

            ForEach(matching, id: \.id) { entry in
                HStack(spacing: 6) {
                    let color = activities.firstIndex(where: { $0.activity.title == entry.activity })
                        .map { palette[$0 % palette.count] } ?? .secondary
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                    Text(entry.activity)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(formatHours(entry.value))
                        .font(.caption.monospacedDigit())
                }
            }

            if matching.count > 1 {
                Divider()
                HStack {
                    Text("Total")
                        .font(.caption.bold())
                    Spacer()
                    Text(formatHours(bucketTotal))
                        .font(.caption.bold().monospacedDigit())
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

// MARK: - Activity Breakdown Card

private struct ActivityBreakdownCard: View {
    @Environment(AppState.self) private var appState
    @State private var expandedActivities: Set<Int64> = []
    @State private var todaySessions: [Int64: [Session]] = [:]

    var body: some View {
        ChartCard(title: "Activity Breakdown") {
            if appState.todayActivities.isEmpty {
                ContentUnavailableView(
                    "No Activity Yet",
                    systemImage: "chart.bar",
                    description: Text("Start a session to see your activity breakdown.")
                )
                .emptyStateStyle()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(appState.todayActivities.enumerated()), id: \.element.activity.id) { index, summary in
                        let activityId = summary.activity.id ?? -1
                        let isExpanded = expandedActivities.contains(activityId)

                        VStack(spacing: 0) {
                            HStack {
                                if summary.sessionCount > 1 {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(summary.activity.title)
                                        .font(.body)
                                        .lineLimit(1)

                                    Text("\(summary.sessionCount) \(summary.sessionCount == 1 ? "session" : "sessions")")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(TimeFormatting.formatDuration(seconds: summary.totalSeconds))
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, Constants.spacingCompact)
                            .padding(.horizontal, Constants.spacingCard)
                            .background(index.isMultiple(of: 2) ? Color.clear : Color.gray.opacity(0.08))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard summary.sessionCount > 1 else { return }
                                withAdaptiveAnimation(.easeInOut(duration: 0.2)) {
                                    if isExpanded {
                                        expandedActivities.remove(activityId)
                                    } else {
                                        expandedActivities.insert(activityId)
                                        loadSessionsForActivity(activityId)
                                    }
                                }
                            }

                            if isExpanded, let sessions = todaySessions[activityId] {
                                ForEach(sessions) { session in
                                    HStack {
                                        Text(SessionTypeConfig.config(for: session.sessionType).displayName)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)

                                        Text(TimeFormatting.formatTime(session.startedAt))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)

                                        Spacer()

                                        if let duration = session.durationSeconds {
                                            Text(TimeFormatting.formatDuration(seconds: duration))
                                                .font(.subheadline.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
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
                .padding(.bottom, Constants.spacingCard)
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
                todaySessions[activityId] = sessions.map(\.0).sorted {
                    ($0.endedAt ?? .distantFuture) > ($1.endedAt ?? .distantFuture)
                }
            } catch {
                // Fail silently — the row just won't expand
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
