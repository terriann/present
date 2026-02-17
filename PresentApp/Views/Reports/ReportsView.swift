import SwiftUI
import Charts
import PresentCore

struct ReportsView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var selectedPeriod: ReportPeriod = .daily
    @State private var selectedDate: Date = Date()
    @State private var includeArchived = false
    @State private var activities: [ActivitySummary] = []
    @State private var totalSeconds: Int = 0
    @State private var sessionCount: Int = 0
    @State private var dailySummaryData: DailySummary?
    @State private var weeklySummaryData: WeeklySummary?
    @State private var monthlySummaryData: MonthlySummary?
    @State private var tagSummaries: [TagSummary] = []

    // Navigation state
    @State private var earliestDate: Date?
    @State private var weekStartDay: Int = 1 // Calendar.firstWeekday: 1=Sunday, 2=Monday

    // Hover state
    @State private var hoveredBarLabel: String?
    @State private var barHoverLocation: CGPoint = .zero
    @State private var activityAngleSelection: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                controlsBar
                periodNavigationBar
                summaryBar

                if !activities.isEmpty {
                    stackedBarChartCard
                    HStack(alignment: .top, spacing: 16) {
                        activityPieChartCard
                            .frame(maxWidth: .infinity)
                        if !tagSummaries.isEmpty {
                            tagBarChartCard
                                .frame(maxWidth: .infinity)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Text("Use present-cli report export for CSV export")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .navigationTitle("Reports")
        .task {
            await loadInitialState()
            await loadReport()
        }
        .onChange(of: selectedPeriod) {
            Task { await loadReport() }
        }
        .onChange(of: selectedDate) {
            Task { await loadReport() }
        }
        .onChange(of: includeArchived) {
            Task { await loadReport() }
        }
    }

    // MARK: - Controls

    private var controlsBar: some View {
        HStack {
            Picker("", selection: $selectedPeriod) {
                ForEach(ReportPeriod.allCases, id: \.self) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 250)

            Spacer()

            Toggle("Hide archived", isOn: Binding(
                get: { !includeArchived },
                set: { includeArchived = !$0 }
            ))
            .toggleStyle(ThemedToggleStyle(tintColor: theme.accent))
        }
    }

    // MARK: - Period Navigation

    private var periodNavigationBar: some View {
        HStack {
            Button {
                navigatePeriod(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!canNavigateBack)
            .buttonStyle(.borderless)

            Text(periodHeaderText)
                .font(.headline)
                .frame(minWidth: 200)

            Button {
                navigatePeriod(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!canNavigateForward)
            .buttonStyle(.borderless)

            Spacer()
        }
    }

    private var periodHeaderText: String {
        let calendar = Calendar.current
        switch selectedPeriod {
        case .daily:
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            return formatter.string(from: selectedDate)
        case .weekly:
            let weekStart = weekStart(for: selectedDate)
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            let startFormatter = DateFormatter()
            let endFormatter = DateFormatter()
            if calendar.component(.year, from: weekStart) == calendar.component(.year, from: weekEnd) {
                startFormatter.dateFormat = "MMMM d"
                endFormatter.dateFormat = "MMMM d, yyyy"
            } else {
                startFormatter.dateFormat = "MMMM d, yyyy"
                endFormatter.dateFormat = "MMMM d, yyyy"
            }
            return "\(startFormatter.string(from: weekStart)) – \(endFormatter.string(from: weekEnd))"
        case .monthly:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: selectedDate)
        }
    }

    private var canNavigateBack: Bool {
        guard let earliest = earliestDate else { return false }
        let periodStart = periodStartDate(for: selectedDate)
        return periodStart > Calendar.current.startOfDay(for: earliest)
    }

    private var canNavigateForward: Bool {
        let today = Date()
        let periodEnd = periodEndDate(for: selectedDate)
        return periodEnd <= today
    }

    private func navigatePeriod(by offset: Int) {
        let calendar = Calendar.current
        switch selectedPeriod {
        case .daily:
            if let newDate = calendar.date(byAdding: .day, value: offset, to: selectedDate) {
                selectedDate = newDate
            }
        case .weekly:
            if let newDate = calendar.date(byAdding: .weekOfYear, value: offset, to: selectedDate) {
                selectedDate = newDate
            }
        case .monthly:
            if let newDate = calendar.date(byAdding: .month, value: offset, to: selectedDate) {
                selectedDate = newDate
            }
        }
    }

    private func periodStartDate(for date: Date) -> Date {
        let calendar = Calendar.current
        switch selectedPeriod {
        case .daily:
            return calendar.startOfDay(for: date)
        case .weekly:
            return weekStart(for: date)
        case .monthly:
            return calendar.dateInterval(of: .month, for: date)!.start
        }
    }

    private func periodEndDate(for date: Date) -> Date {
        let calendar = Calendar.current
        switch selectedPeriod {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!
        case .weekly:
            let start = weekStart(for: date)
            return calendar.date(byAdding: .day, value: 7, to: start)!
        case .monthly:
            return calendar.dateInterval(of: .month, for: date)!.end
        }
    }

    /// Compute week start date respecting weekStartDay preference.
    private func weekStart(for date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = weekStartDay
        return calendar.dateInterval(of: .weekOfYear, for: date)!.start
    }

    private var summaryBar: some View {
        HStack(spacing: 40) {
            VStack {
                Text(TimeFormatting.formatDuration(seconds: totalSeconds))
                    .font(.title.bold())
                Text("Total Time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack {
                Text("\(sessionCount)")
                    .font(.title.bold())
                Text("Sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack {
                Text("\(activities.count)")
                    .font(.title.bold())
                Text("Activities")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Chart Colors

    private var chartColorDomain: [String] {
        activities.map(\.activity.title)
    }

    private var chartColorRange: [Color] {
        let palette = ThemeManager.chartColors(for: theme.activePalette)
        return activities.indices.map { palette[$0 % palette.count] }
    }

    // MARK: - X-Axis Domains

    private var allHourLabels: [String] {
        (0..<24).map { hourLabel($0) }
    }

    private var allWeekdayLabels: [String] {
        var calendar = Calendar.current
        calendar.firstWeekday = weekStartDay
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        let start = weekStart(for: selectedDate)
        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            return formatter.string(from: date)
        }
    }

    private var allDayNumberLabels: [String] {
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: selectedDate)!
        return range.map { String($0) }
    }

    private var xAxisDomain: [String] {
        switch selectedPeriod {
        case .daily: return allHourLabels
        case .weekly: return allWeekdayLabels
        case .monthly: return allDayNumberLabels
        }
    }

    // MARK: - Stacked Bar Chart

    private var barEntries: [BarEntry] {
        switch selectedPeriod {
        case .daily:
            let buckets = dailySummaryData?.hourlyBreakdown ?? []
            return buckets.map { bucket in
                BarEntry(
                    label: hourLabel(bucket.hour),
                    activity: bucket.activity.title,
                    value: Double(bucket.totalSeconds) / 60.0
                )
            }
        case .weekly:
            let dailyBreakdown = weeklySummaryData?.dailyBreakdown ?? []
            return dailyBreakdown.flatMap { daily in
                daily.activities.map { summary in
                    BarEntry(
                        label: dayLabel(daily.date),
                        activity: summary.activity.title,
                        value: Double(summary.totalSeconds) / 3600.0
                    )
                }
            }
        case .monthly:
            let dailyBreakdown = monthlySummaryData?.dailyBreakdown ?? []
            return dailyBreakdown.flatMap { daily in
                daily.activities.map { summary in
                    BarEntry(
                        label: dayNumberLabel(daily.date),
                        activity: summary.activity.title,
                        value: Double(summary.totalSeconds) / 3600.0
                    )
                }
            }
        }
    }

    private var yAxisLabel: String {
        selectedPeriod == .daily ? "Minutes" : "Hours"
    }

    private var yAxisDomain: ClosedRange<Double> {
        let entries = barEntries
        switch selectedPeriod {
        case .daily:
            return 0...60
        case .weekly, .monthly:
            // Group by label, sum values, find peak
            var labelTotals: [String: Double] = [:]
            for entry in entries {
                labelTotals[entry.label, default: 0] += entry.value
            }
            let peak = labelTotals.values.max() ?? 0
            return 0...max(18, peak)
        }
    }

    private var stackedBarChartCard: some View {
        let entries = barEntries
        let domain = xAxisDomain

        return GroupBox {
            Chart(entries, id: \.id) { entry in
                BarMark(
                    x: .value(selectedPeriod.timeLabel, entry.label),
                    y: .value(yAxisLabel, entry.value)
                )
                .foregroundStyle(by: .value("Activity", entry.activity))
                .opacity(hoveredBarLabel == nil || hoveredBarLabel == entry.label ? 1.0 : 0.4)
            }
            .chartForegroundStyleScale(domain: chartColorDomain, range: chartColorRange)
            .chartXScale(domain: domain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: selectedPeriod == .monthly ? 15 : 12))
            }
            .chartYScale(domain: yAxisDomain)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(selectedPeriod == .daily ? "\(Int(v))m" : "\(Int(v))h")
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    let plotFrame = geometry[proxy.plotAreaFrame]

                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let relativeX = location.x - plotFrame.origin.x
                                if let label: String = proxy.value(atX: relativeX) {
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
                        barTooltip(for: label, entries: entries)
                            .fixedSize()
                            .frame(maxWidth: 180, alignment: .leading)
                            .position(x: pos.x, y: pos.y)
                    }
                }
            }
            .frame(height: 250)
            .padding(4)
        } label: {
            Text("Time by \(selectedPeriod.timeLabel)")
                .font(.subheadline.weight(.semibold))
        }
    }

    private func barTooltip(for label: String, entries: [BarEntry]) -> some View {
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
                    Text(formatValue(entry.value))
                        .font(.caption.monospacedDigit())
                }
            }

            if matching.count > 1 {
                Divider()
                HStack {
                    Text("Total")
                        .font(.caption.bold())
                    Spacer()
                    Text(formatValue(bucketTotal))
                        .font(.caption.bold().monospacedDigit())
                }
            }
        }
    }

    // MARK: - Activity Pie Chart

    private var hoveredActivityName: String? {
        findActivity(for: activityAngleSelection)
    }

    private func findActivity(for value: Int?) -> String? {
        guard let value else { return nil }
        var cumulative = 0
        for summary in activities {
            cumulative += summary.totalSeconds
            if value <= cumulative {
                return summary.activity.title
            }
        }
        return nil
    }

    private var activityPieChartCard: some View {
        GroupBox {
            Chart(activities, id: \.activity.id) { summary in
                SectorMark(
                    angle: .value("Time", summary.totalSeconds),
                    innerRadius: .ratio(0.5),
                    angularInset: 1
                )
                .foregroundStyle(by: .value("Activity", summary.activity.title))
                .opacity(hoveredActivityName == nil || hoveredActivityName == summary.activity.title ? 1.0 : 0.4)
            }
            .chartForegroundStyleScale(domain: chartColorDomain, range: chartColorRange)
            .chartAngleSelection(value: $activityAngleSelection)
            .chartLegend(position: .trailing, alignment: .center, spacing: 12)
            .overlay {
                if let name = hoveredActivityName,
                   let summary = activities.first(where: { $0.activity.title == name }) {
                    donutCenterTooltip {
                        Text(summary.activity.title)
                            .font(.caption.bold())
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        Text(TimeFormatting.formatDuration(seconds: summary.totalSeconds))
                            .font(.caption.monospacedDigit())
                        let pct = totalSeconds > 0 ? Double(summary.totalSeconds) / Double(totalSeconds) * 100 : 0
                        Text(String(format: "%.1f%%", pct))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(summary.sessionCount) sessions")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 250)
            .padding(4)
        } label: {
            Text("Activity Distribution")
                .font(.subheadline.weight(.semibold))
        }
    }

    // MARK: - Tag Bar Chart

    private var tagBarChartCard: some View {
        let palette = ThemeManager.chartColors(for: theme.activePalette)
        let sorted = tagSummaries.sorted { $0.totalSeconds > $1.totalSeconds }
        let colorMap = Dictionary(uniqueKeysWithValues: sorted.enumerated().map { ($1.tagName, palette[$0 % palette.count]) })
        let barHeight: CGFloat = max(120, CGFloat(sorted.count) * 36 + 40)

        return GroupBox {
            Chart(sorted, id: \.tagName) { summary in
                BarMark(
                    x: .value("Hours", Double(summary.totalSeconds) / 3600.0),
                    y: .value("Tag", summary.tagName)
                )
                .foregroundStyle(colorMap[summary.tagName] ?? .secondary)
                .annotation(position: .trailing, spacing: 6) {
                    Text(TimeFormatting.formatDuration(seconds: summary.totalSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .chartLegend(.hidden)
            .chartXAxis {
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
            .frame(height: barHeight)
            .padding(4)
        } label: {
            Text("Tag Distribution")
                .font(.subheadline.weight(.semibold))
        }
    }

    // MARK: - Helpers

    /// Calculates tooltip center position near the cursor, flipping sides and clamping to stay
    /// at least 1em (16pt) from each edge of the container.
    private func tooltipPosition(cursor: CGPoint, containerSize: CGSize) -> CGPoint {
        let tooltipWidth: CGFloat = 180
        let tooltipHeight: CGFloat = 100
        let edgePadding: CGFloat = 16
        let cursorOffset: CGFloat = 12

        // Horizontal: prefer right of cursor, flip left if overflow
        let xRight = cursor.x + cursorOffset
        let xLeft = cursor.x - cursorOffset - tooltipWidth
        let originX: CGFloat
        if xRight + tooltipWidth + edgePadding <= containerSize.width {
            originX = xRight
        } else if xLeft >= edgePadding {
            originX = xLeft
        } else {
            originX = min(max(edgePadding, xRight), containerSize.width - tooltipWidth - edgePadding)
        }

        // Vertical: prefer above cursor, flip below if overflow
        let yAbove = cursor.y - cursorOffset - tooltipHeight
        let yBelow = cursor.y + cursorOffset
        let originY: CGFloat
        if yAbove >= edgePadding {
            originY = yAbove
        } else if yBelow + tooltipHeight + edgePadding <= containerSize.height {
            originY = yBelow
        } else {
            originY = max(edgePadding, yAbove)
        }

        // .position() expects center, not origin
        return CGPoint(x: originX + tooltipWidth / 2, y: originY + tooltipHeight / 2)
    }

    private func hourLabel(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date).lowercased()
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func dayNumberLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    /// Format a value for tooltip display, using the correct unit for the period.
    private func formatValue(_ value: Double) -> String {
        if selectedPeriod == .daily {
            // Value is in minutes
            if value < 1 {
                return String(format: "%.0fs", value * 60)
            }
            return String(format: "%.0fm", value)
        } else {
            // Value is in hours
            if value < 0.1 {
                let minutes = value * 60
                return String(format: "%.0fm", minutes)
            }
            return String(format: "%.1fh", value)
        }
    }

    // MARK: - Data Loading

    private func loadInitialState() async {
        do {
            earliestDate = try await appState.service.earliestSessionDate()
            if let weekStartPref = try await appState.service.getPreference(key: PreferenceKey.weekStartDay) {
                weekStartDay = PreferenceKey.parseWeekStartDay(weekStartPref)
            }
        } catch {
            print("Error loading initial state: \(error)")
        }
    }

    private func loadReport() async {
        do {
            var calendar = Calendar.current
            calendar.firstWeekday = weekStartDay

            switch selectedPeriod {
            case .daily:
                let summary = try await appState.service.dailySummary(date: selectedDate, includeArchived: includeArchived)
                dailySummaryData = summary
                activities = summary.activities
                totalSeconds = summary.totalSeconds
                sessionCount = summary.sessionCount

                let startOfDay = calendar.startOfDay(for: selectedDate)
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
                tagSummaries = try await appState.service.tagSummary(from: startOfDay, to: endOfDay, includeArchived: includeArchived)

            case .weekly:
                let summary = try await appState.service.weeklySummary(weekOf: selectedDate, includeArchived: includeArchived)
                weeklySummaryData = summary
                activities = summary.activities
                totalSeconds = summary.totalSeconds
                sessionCount = summary.sessionCount

                let wStart = weekStart(for: selectedDate)
                let weekEnd = calendar.date(byAdding: .day, value: 7, to: wStart)!
                tagSummaries = try await appState.service.tagSummary(from: wStart, to: weekEnd, includeArchived: includeArchived)

            case .monthly:
                let summary = try await appState.service.monthlySummary(monthOf: selectedDate, includeArchived: includeArchived)
                monthlySummaryData = summary
                activities = summary.activities
                totalSeconds = summary.totalSeconds
                sessionCount = summary.sessionCount

                let monthInterval = calendar.dateInterval(of: .month, for: selectedDate)!
                tagSummaries = try await appState.service.tagSummary(from: monthInterval.start, to: monthInterval.end, includeArchived: includeArchived)
            }
        } catch {
            print("Error loading report: \(error)")
        }
    }
}

// MARK: - Supporting Types

enum ReportPeriod: String, CaseIterable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"

    var timeLabel: String {
        switch self {
        case .daily: "Hour"
        case .weekly: "Day"
        case .monthly: "Day"
        }
    }
}

private struct BarEntry: Identifiable {
    let id = UUID()
    let label: String
    let activity: String
    let value: Double
}

// MARK: - Tooltip Views

/// Floating tooltip card for bar chart hover.
private struct ChartTooltip<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            content
        }
        .padding(8)
        .frame(maxWidth: 180)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .allowsHitTesting(false)
    }
}

/// Centered tooltip displayed in the donut hole on hover.
private struct donutCenterTooltip<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 2) {
            content
        }
        .frame(maxWidth: 100)
        .allowsHitTesting(false)
    }
}
