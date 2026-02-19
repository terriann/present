import SwiftUI
import Charts
import PresentCore

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var hoveredBarLabel: String?
    @State private var barHoverLocation: CGPoint = .zero

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Current session
                if appState.isSessionActive {
                    currentSessionCard
                }

                // Today's summary
                todaySummaryCard

                // Weekly chart
                if let weekly = appState.weeklySummary, !weekly.activities.isEmpty {
                    weeklyChartCard(weekly)
                }

                // Activity breakdown
                activityBreakdownCard
            }
            .padding(20)
        }
        .navigationTitle("Dashboard")
        .alert(appState.isLongBreak ? "Time for a Long Break!" : "Take a Short Break",
               isPresented: Bindable(appState).showBreakSuggestion) {
            Button("OK") { appState.dismissBreakSuggestion() }
        } message: {
            Text("You've earned a \(appState.suggestedBreakMinutes)-minute break. Step away and recharge.")
        }
    }

    // MARK: - Current Session Card

    private var currentSessionCard: some View {
        GroupBox {
            Text("Current Session")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 12)

            if let activity = appState.currentActivity, let session = appState.currentSession {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(activity.title)
                                .font(.title3.bold())

                            Text(SessionTypeConfig.config(for: session.sessionType).displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(appState.formattedTimerValue)
                            .font(.system(size: 42, weight: .light, design: .monospaced))
                            .contentTransition(.numericText())
                    }

                    SessionControls()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Today's Summary

    private var todaySummaryCard: some View {
        VStack(spacing: 12) {
            Text(Date.now.formatted(date: .complete, time: .omitted))
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

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
        }
    }

    // MARK: - Weekly Chart

    private func weeklyChartCard(_ weekly: WeeklySummary) -> some View {
        let entries = weeklyBarEntries(weekly)
        let domain = weekdayLabels(weekly)

        return ChartCard(title: "This Week") {
            weeklyBarChart(entries: entries, domain: domain, activities: weekly.activities)
        }
    }

    private func weeklyBarChart(entries: [DashboardBarEntry], domain: [String], activities: [ActivitySummary]) -> some View {
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

        return Chart(entries, id: \.id) { entry in
            BarMark(
                x: .value("Day", entry.label),
                y: .value("Hours", entry.value)
            )
            .foregroundStyle(by: .value("Activity", entry.activity))
            .opacity(hoveredBarLabel == nil || hoveredBarLabel == entry.label ? 1.0 : 0.4)
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
                        weeklyBarTooltip(for: label, entries: entries, activities: activities)
                            .fixedSize()
                            .frame(maxWidth: 180, alignment: .leading)
                            .position(x: pos.x, y: pos.y)
                    }
                }
            }
        }
        .chartLegend(position: .bottom, spacing: 12)
        .frame(height: 250)
        .padding(12)
    }

    private func weeklyBarTooltip(for label: String, entries: [DashboardBarEntry], activities: [ActivitySummary]) -> some View {
        let matching = entries.filter { $0.label == label }
        let bucketTotal = matching.reduce(0.0) { $0 + $1.value }
        let palette = ThemeManager.chartColors(for: theme.activePalette)

        return ChartTooltip {
            Text(label)
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
                    ForEach(appState.todayActivities, id: \.activity.id) { summary in
                        HStack {
                            Text(summary.activity.title)
                                .lineLimit(1)

                            Spacer()

                            Text("\(summary.sessionCount) sessions")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(TimeFormatting.formatDuration(seconds: summary.totalSeconds))
                                .font(.body.monospacedDigit())
                                .frame(width: 80, alignment: .trailing)
                        }
                        .padding(.vertical, 6)

                        if summary.activity.id != appState.todayActivities.last?.activity.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }
}

// MARK: - Supporting Types

private struct DashboardBarEntry: Identifiable {
    let id = UUID()
    let label: String
    let activity: String
    let value: Double
}
