import SwiftUI
import Charts
import PresentCore

struct DashboardWeeklyChartCard: View {
    let activityColorMap: [String: Color]
    let chartColorDomain: [String]
    let chartColorRange: [Color]
    let weekly: WeeklySummary
    let hasActiveTodaySession: Bool
    let todayPortionSeconds: Int
    let currentActivity: Activity?
    let reduceMotion: Bool

    @Environment(AppState.self) private var appState

    @State private var hoveredBarLabel: String?
    @State private var hoveredBarActivity: String?
    @State private var barHoverLocation: CGPoint = .zero
    /// Drives the gentle pulse on the active session's bar segment.
    @State private var pulseState = ActivePulseState()

    var body: some View {
        // Guard: chartForegroundStyleScale crashes on empty domain (FB…).
        if !chartColorDomain.isEmpty {
            let entries = weeklyBarEntries()
            let domain = weekdayLabels()
            let tooltipLabels = weeklyTooltipLabels(weekStartDay: appState.weekStartDay, referenceDate: Date())

            ChartCard(title: "Your Week", subtitle: weekRangeTitle) {
                weeklyBarChart(entries: entries, domain: domain, activities: weekly.activities, tooltipLabels: tooltipLabels)
                weeklyBarChartLegend
            }
            .onChange(of: hasActiveTodaySession) {
                if hasActiveTodaySession {
                    pulseState.start(reduceMotion: reduceMotion)
                } else {
                    pulseState.stop()
                }
            }
            .onAppear {
                if hasActiveTodaySession {
                    pulseState.start(reduceMotion: reduceMotion)
                }
            }
            .onDisappear {
                pulseState.stop()
            }
        }
    }

    // MARK: - Week Range Title

    private var weekRangeTitle: String {
        var calendar = Calendar.current
        calendar.firstWeekday = appState.weekStartDay
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return "This Week" }
        let start = interval.start
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        return TimeFormatting.formatWeekRange(start: start, end: end)
    }

    // MARK: - Bar Chart

    private func weeklyBarChart(entries: [DashboardBarEntry], domain: [String], activities: [ActivitySummary], tooltipLabels: [String: String]) -> some View {
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
        .chartForegroundStyleScale(domain: chartColorDomain, range: chartColorRange)
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

    // MARK: - Tooltip

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

    // MARK: - Opacity

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
        if entry.isActive { return pulseState.opacity }
        return 1.0
    }

    // MARK: - Legend

    private var weeklyBarChartLegend: some View {
        let items = zip(chartColorDomain, chartColorRange).map { (label: $0, color: $1) }
        return HoverableChartLegend(
            items: items,
            hoveredLabel: $hoveredBarActivity
        )
        .padding(.horizontal, Constants.spacingCard)
        .padding(.bottom, Constants.spacingCard)
    }

    // MARK: - Data Helpers

    private func weeklyBarEntries() -> [DashboardBarEntry] {
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
        if hasActiveTodaySession, let activity = currentActivity, !activity.isSystem {
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

    private func weekdayLabels() -> [String] {
        var calendar = Calendar.current
        calendar.firstWeekday = appState.weekStartDay
        guard let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return [] }
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return ChartFormatters.weekday.string(from: date)
        }
    }

    private func dayLabel(_ date: Date) -> String {
        ChartFormatters.weekday.string(from: date)
    }

    private func formatHours(_ value: Double) -> String {
        TimeFormatting.formatDuration(seconds: Int((value * 3600).rounded()))
    }
}

// MARK: - Supporting Types

struct DashboardBarEntry: Identifiable {
    var id: String { "\(label)-\(activity)" }
    let label: String
    let activity: String
    let value: Double
    var isActive: Bool = false
}
