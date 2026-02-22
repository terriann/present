import SwiftUI
import Charts
import PresentCore

struct ReportsView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var selectedPeriod: ReportPeriod = .daily
    @State private var selectedDate: Date = Date()
    @State private var hideArchived = false
    @State private var activities: [ActivitySummary] = []
    @State private var totalSeconds: Int = 0
    @State private var sessionCount: Int = 0
    @State private var dailySummaryData: DailySummary?
    @State private var weeklySummaryData: WeeklySummary?
    @State private var monthlySummaryData: MonthlySummary?
    @State private var tagActivitySummaries: [TagActivitySummary] = []
    @State private var sessionEntries: [(Session, Activity)] = []

    // Navigation state
    @State private var earliestDate: Date?
    @State private var weekStartDay: Int = 1 // Calendar.firstWeekday: 1=Sunday, 2=Monday
    @State private var loadTask: Task<Void, Never>?

    // CLI promo card
    @State private var currentCommandIndex = 0
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Hover state
    @State private var hoveredBarLabel: String?
    @State private var barHoverLocation: CGPoint = .zero
    @State private var activityAngleSelection: Int?
    @State private var hoveredActivityName: String?
    @State private var legendHoveredActivity: String?
    @State private var hoveredTagName: String?
    @State private var tagHoverLocation: CGPoint = .zero
    @State private var externalIdAngleSelection: Int?
    @State private var hoveredExternalSegment: String?

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
                        if !tagActivitySummaries.isEmpty {
                            tagBarChartCard
                                .frame(maxWidth: .infinity)
                        }
                    }
                    if !externalIdGroups.isEmpty {
                        externalIdBreakdownCard
                    }
                } else {
                    let includesToday = periodStartDate(for: selectedDate) <= Date() && Date() < periodEndDate(for: selectedDate)
                    GroupBox {
                        ContentUnavailableView(
                            "No Data",
                            systemImage: "chart.pie",
                            description: Text(includesToday
                                ? "No sessions recorded for this period. Start tracking to see your reports."
                                : "No sessions recorded for this period.")
                        )
                        .emptyStateStyle()
                    }
                }

                sessionLogCard
                cliPromoCard
            }
            .padding(Constants.spacingPage)
        }
        .navigationTitle("Reports")
        .task {
            await loadInitialState()
            await loadReport()
        }
        .onChange(of: selectedPeriod) { oldPeriod, newPeriod in
            if let target = drillDownDate(from: oldPeriod, to: newPeriod), target != selectedDate {
                selectedDate = target  // onChange(of: selectedDate) will trigger reload
                return
            }
            reloadReport()
        }
        .onChange(of: selectedDate) {
            reloadReport()
        }
        .onChange(of: hideArchived) {
            reloadReport()
        }
    }

    // MARK: - Controls

    private var controlsBar: some View {
        HStack {
            Picker(selection: $selectedPeriod, label: EmptyView()) {
                ForEach(ReportPeriod.allCases, id: \.self) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Spacer()

            Toggle("Hide archived", isOn: $hideArchived)
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
                .font(.periodHeader)
                .frame(minWidth: 200)

            Button {
                navigatePeriod(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!canNavigateForward)
            .buttonStyle(.borderless)

            Button {
                selectedDate = Date()
            } label: {
                Image(systemName: "calendar")
            }
            .buttonStyle(.borderless)
            .disabled(isShowingToday)
            .foregroundStyle(isShowingToday ? .secondary : theme.accent)

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
            return TimeFormatting.formatWeekRange(start: weekStart, end: weekEnd)
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

    private var isShowingToday: Bool {
        let today = Date()
        let currentPeriodStart = periodStartDate(for: selectedDate)
        let currentPeriodEnd = periodEndDate(for: selectedDate)
        return today >= currentPeriodStart && today < currentPeriodEnd
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
            return calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        }
    }

    private func periodEndDate(for date: Date) -> Date {
        let calendar = Calendar.current
        switch selectedPeriod {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        case .weekly:
            let start = weekStart(for: date)
            return calendar.date(byAdding: .day, value: 7, to: start) ?? date
        case .monthly:
            return calendar.dateInterval(of: .month, for: date)?.end ?? date
        }
    }

    /// Compute week start date respecting weekStartDay preference.
    private func weekStart(for date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = weekStartDay
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private var summaryBar: some View {
        HStack(spacing: 40) {
            StatItem(
                title: "Total Time",
                value: TimeFormatting.formatDuration(seconds: totalSeconds)
            )

            StatItem(
                title: "Sessions",
                value: "\(sessionCount)"
            )

            StatItem(
                title: "Activities",
                value: "\(activities.count)"
            )

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
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return formatter.string(from: date)
        }
    }

    private var allDayNumberLabels: [String] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: selectedDate) else { return [] }
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
        var labelTotals: [String: Double] = [:]
        for entry in barEntries {
            labelTotals[entry.label, default: 0] += entry.value
        }
        let peak = labelTotals.values.max() ?? 0
        let rounded = max(5, ceil(peak / 5) * 5)
        if selectedPeriod == .daily {
            return 0...rounded
        } else {
            // +1 so the rounded multiple appears as a visible axis mark
            return 0...min(rounded + 1, 25)
        }
    }

    private var weeklyTooltipLabelMap: [String: String] {
        guard selectedPeriod == .weekly else { return [:] }
        return weeklyTooltipLabels(weekStartDay: weekStartDay, referenceDate: selectedDate)
    }

    private var stackedBarChartCard: some View {
        let entries = barEntries
        let domain = xAxisDomain
        let tooltipLabels = weeklyTooltipLabelMap

        return ChartCard(title: "Time by \(selectedPeriod.timeLabel)") {
            stackedBarChart(entries: entries, domain: domain, tooltipLabels: tooltipLabels)
        }
    }

    private var weekendDayLabels: Set<String> {
        switch selectedPeriod {
        case .daily:
            return []
        case .weekly:
            return weekendLabels(period: .weekly, weekStartDay: weekStartDay, selectedDate: selectedDate)
        case .monthly:
            return weekendLabels(period: .monthly, weekStartDay: weekStartDay, selectedDate: selectedDate)
        }
    }

    private func stackedBarChart(entries: [BarEntry], domain: [String], tooltipLabels: [String: String] = [:]) -> some View {
        let weekends = weekendDayLabels

        return Chart {
            ForEach(Array(weekends), id: \.self) { label in
                RectangleMark(x: .value(selectedPeriod.timeLabel, label))
                    .foregroundStyle(Color.gray.opacity(0.08))
                    .zIndex(-1)
            }

            ForEach(entries, id: \.id) { entry in
                BarMark(
                    x: .value(selectedPeriod.timeLabel, entry.label),
                    y: .value(yAxisLabel, entry.value)
                )
                .foregroundStyle(by: .value("Activity", entry.activity))
                .opacity(hoveredBarLabel == nil || hoveredBarLabel == entry.label ? 1.0 : 0.4)
            }
        }
        .chartForegroundStyleScale(domain: chartColorDomain, range: chartColorRange)
        .chartXScale(domain: domain)
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisTick()
                if let label = value.as(String.self), shouldShowXAxisLabel(label) {
                    AxisValueLabel()
                }
            }
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
                        barTooltip(for: label, entries: entries, tooltipLabels: tooltipLabels)
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

    private func barTooltip(for label: String, entries: [BarEntry], tooltipLabels: [String: String] = [:]) -> some View {
        let matching = entries.filter { $0.label == label }
        let bucketTotal = matching.reduce(0.0) { $0 + $1.value }
        let palette = ThemeManager.chartColors(for: theme.activePalette)

        return ChartTooltip {
            Text(tooltipLabels[label] ?? label)
                .font(.dataLabel)

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
                        .font(.dataValue)
                }
            }

            if matching.count > 1 {
                Divider()
                HStack {
                    Text("Total")
                        .font(.dataLabel)
                    Spacer()
                    Text(formatValue(bucketTotal))
                        .font(.dataBoldValue)
                }
            }
        }
    }

    private func tagTooltip(forTag tagName: String?, summaries: [TagActivitySummary]) -> some View {
        let matching = summaries.first { $0.tagName == tagName }
        let palette = ThemeManager.chartColors(for: theme.activePalette)

        return ChartTooltip {
            if let tag = matching {
                Text(tag.tagName)
                    .font(.dataLabel)

                ForEach(tag.activities, id: \.activity.id) { summary in
                    HStack(spacing: 6) {
                        let color = activities.firstIndex(where: { $0.activity.title == summary.activity.title })
                            .map { palette[$0 % palette.count] } ?? .secondary
                        Circle()
                            .fill(color)
                            .frame(width: 8, height: 8)
                        Text(summary.activity.title)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(TimeFormatting.formatDuration(seconds: summary.totalSeconds))
                            .font(.dataValue)
                    }
                }

                if tag.activities.count > 1 {
                    Divider()
                    HStack {
                        Text("Total")
                            .font(.dataLabel)
                        Spacer()
                        Text(TimeFormatting.formatDuration(seconds: tag.totalSeconds))
                            .font(.dataBoldValue)
                    }
                }
            }
        }
    }

    // MARK: - External ID Breakdown Chart

    private var externalIdGroups: [(externalId: String, activities: [ActivitySummary], totalSeconds: Int)] {
        var grouped: [String: [ActivitySummary]] = [:]
        for summary in activities {
            if let externalId = summary.activity.externalId {
                grouped[externalId, default: []].append(summary)
            }
        }
        return grouped.map { (externalId: $0.key, activities: $0.value, totalSeconds: $0.value.reduce(0) { $0 + $1.totalSeconds }) }
            .sorted { $0.totalSeconds > $1.totalSeconds }
    }

    private var externalActivitiesSeconds: Int {
        externalIdGroups.reduce(0) { $0 + $1.totalSeconds }
    }

    private func findExternalSegment(for value: Int?) -> String? {
        guard let value else { return nil }
        var cumulative = 0
        for group in externalIdGroups {
            cumulative += group.totalSeconds
            if value <= cumulative {
                return group.externalId
            }
        }
        return nil
    }

    private var externalIdBreakdownCard: some View {
        let groups = externalIdGroups
        let combinedTotal = groups.reduce(0) { $0 + $1.totalSeconds }
        let palette = ThemeManager.chartColors(for: theme.activePalette)

        return ChartCard(title: "External ID Breakdown") {
            externalIdDonutChart(groups: groups, combinedTotal: combinedTotal, palette: palette)
            externalIdLegend(groups: groups, palette: palette)
        }
    }

    private func externalIdDonutChart(
        groups: [(externalId: String, activities: [ActivitySummary], totalSeconds: Int)],
        combinedTotal: Int,
        palette: [Color]
    ) -> some View {
        Chart(groups, id: \.externalId) { group in
            SectorMark(
                angle: .value("Time", group.totalSeconds),
                innerRadius: .ratio(0.5),
                angularInset: 1
            )
            .foregroundStyle(by: .value("External ID", group.externalId))
            .opacity(hoveredExternalSegment == nil || hoveredExternalSegment == group.externalId ? 1.0 : 0.4)
        }
        .chartForegroundStyleScale(
            domain: groups.map(\.externalId),
            range: groups.indices.map { palette[$0 % palette.count] }
        )
        .chartAngleSelection(value: $externalIdAngleSelection)
        .onChange(of: externalIdAngleSelection) {
            hoveredExternalSegment = findExternalSegment(for: externalIdAngleSelection)
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    if let segmentId = hoveredExternalSegment,
                       let group = groups.first(where: { $0.externalId == segmentId }) {
                        DonutCenterTooltip {
                            Text(group.externalId)
                                .font(.dataLabel)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            Text(TimeFormatting.formatDuration(seconds: group.totalSeconds))
                                .font(.dataValue)
                            let pct = combinedTotal > 0 ? Double(group.totalSeconds) / Double(combinedTotal) * 100 : 0
                            Text(String(format: "%.1f%%", pct))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            ForEach(group.activities, id: \.activity.id) { summary in
                                Text(summary.activity.title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .position(
                            x: frame.midX,
                            y: frame.midY
                        )
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .frame(height: 250)
        .padding(Constants.spacingCard)
    }

    private func externalIdLegend(
        groups: [(externalId: String, activities: [ActivitySummary], totalSeconds: Int)],
        palette: [Color]
    ) -> some View {
        HoverableChartLegend(
            items: groups.enumerated().map { index, group in
                (label: group.externalId, color: palette[index % palette.count])
            },
            hoveredLabel: $hoveredExternalSegment,
            onHoverEnd: {
                hoveredExternalSegment = findExternalSegment(for: externalIdAngleSelection)
            }
        )
        .padding(.horizontal, Constants.spacingCard)
        .padding(.bottom, Constants.spacingCard)
    }

    // MARK: - Activity Pie Chart

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
        let palette = ThemeManager.chartColors(for: theme.activePalette)

        return ChartCard(title: "Activity Distribution") {
            activityDonutChart
            activityDonutLegend(palette: palette)
        }
    }

    private var activityDonutChart: some View {
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
        .onChange(of: activityAngleSelection) {
            if legendHoveredActivity == nil {
                hoveredActivityName = findActivity(for: activityAngleSelection)
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    if let name = hoveredActivityName,
                       let summary = activities.first(where: { $0.activity.title == name }) {
                        DonutCenterTooltip {
                            Text(summary.activity.title)
                                .font(.dataLabel)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            Text(TimeFormatting.formatDuration(seconds: summary.totalSeconds))
                                .font(.dataValue)
                            let pct = totalSeconds > 0 ? Double(summary.totalSeconds) / Double(totalSeconds) * 100 : 0
                            Text(String(format: "%.1f%%", pct))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(summary.sessionCount) sessions")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .position(
                            x: frame.midX,
                            y: frame.midY
                        )
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .frame(height: 250)
        .padding(Constants.spacingCard)
    }

    private func activityDonutLegend(palette: [Color]) -> some View {
        HoverableChartLegend(
            items: activities.enumerated().map { index, summary in
                (label: summary.activity.title, color: palette[index % palette.count])
            },
            hoveredLabel: $hoveredActivityName,
            onHoverStart: { label in
                legendHoveredActivity = label
            },
            onHoverEnd: {
                legendHoveredActivity = nil
                hoveredActivityName = findActivity(for: activityAngleSelection)
            }
        )
        .padding(.horizontal, Constants.spacingCard)
        .padding(.bottom, Constants.spacingCard)
    }

    // MARK: - Tag Bar Chart

    private var tagBarChartCard: some View {
        let sorted = tagActivitySummaries.sorted { $0.totalSeconds > $1.totalSeconds }
        let barHeight: CGFloat = max(120, CGFloat(sorted.count) * 36 + 40)

        // Flatten into entries for the stacked bar
        let entries: [TagBarEntry] = sorted.flatMap { tag in
            let duration = TimeFormatting.formatDuration(seconds: tag.totalSeconds)
            let yLabel = "\(tag.tagName) · \(duration) (\(tag.activityCount))"
            return tag.activities.map { summary in
                TagBarEntry(
                    tagName: tag.tagName,
                    tagLabel: yLabel,
                    activityTitle: summary.activity.title,
                    hours: Double(summary.totalSeconds) / 3600.0,
                    totalSeconds: tag.totalSeconds
                )
            }
        }

        return ChartCard(title: "Tag Distribution") {
            tagBarChart(entries: entries, sorted: sorted, barHeight: barHeight)
        }
    }

    private func tagBarChart(entries: [TagBarEntry], sorted: [TagActivitySummary], barHeight: CGFloat) -> some View {
        Chart(entries, id: \.id) { entry in
            BarMark(
                x: .value("Hours", entry.hours),
                y: .value("Tag", entry.tagLabel)
            )
            .foregroundStyle(by: .value("Activity", entry.activityTitle))
            .opacity(hoveredTagName == nil || hoveredTagName == entry.tagName ? 1.0 : 0.4)
        }
        .chartForegroundStyleScale(domain: chartColorDomain, range: chartColorRange)
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
                                let relativeY = location.y - frame.origin.y
                                if let label: String = proxy.value(atY: relativeY),
                                   let entry = entries.first(where: { $0.tagLabel == label }) {
                                    hoveredTagName = entry.tagName
                                    tagHoverLocation = location
                                } else {
                                    hoveredTagName = nil
                                }
                            case .ended:
                                hoveredTagName = nil
                            }
                        }

                    if let tagName = hoveredTagName {
                        let pos = tooltipPosition(cursor: tagHoverLocation, containerSize: geometry.size)
                        tagTooltip(forTag: tagName, summaries: sorted)
                            .fixedSize()
                            .frame(maxWidth: 200, alignment: .leading)
                            .position(x: pos.x, y: pos.y)
                    }
                }
            }
        }
        .frame(height: barHeight)
        .padding(Constants.spacingCard)
    }

    // MARK: - Session Log Card

    private var sessionLogCard: some View {
        ChartCard(title: "Session Log") {
            if sessionEntries.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "list.bullet",
                    description: Text("No sessions recorded for this period.")
                )
                .emptyStateStyle()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sessionEntries.enumerated()), id: \.element.0.id) { index, entry in
                        SessionRow(session: entry.0, activityTitle: entry.1.title)
                            .padding(.horizontal, Constants.spacingCard)
                            .padding(.vertical, Constants.spacingCompact)
                            .background(index.isMultiple(of: 2) ? Color.clear : Color.gray.opacity(0.08))
                    }
                }
            }
        }
    }

    // MARK: - CLI Promo Card

    private static let cliCommands: [(command: String, output: String)] = [
        ("$ present-cli session start \"Deep Work\"", "✓ Session started (Focus: 25m)"),
        ("$ present-cli report export --period weekly", "✓ Exported to weekly-report.csv"),
        ("$ present-cli activity list", "  Reading · Writing · Deep Work"),
        ("$ present-cli session stop", "✓ Session saved — 1h 23m"),
    ]

    private var cliPromoCard: some View {
        let pair = Self.cliCommands[currentCommandIndex]

        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "terminal")
                            .foregroundStyle(.secondary)
                        Text("Power up with ")
                            .foregroundStyle(.primary)
                        + Text("present-cli")
                            .font(.codeBlock)
                            .foregroundStyle(.primary)
                    }
                    .font(.headline)

                    Text("Export reports, manage sessions, and automate your workflow from the terminal.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pair.command)
                            .font(.codeCaption)
                            .foregroundStyle(.green)
                        Text(pair.output)
                            .font(.codeCaption)
                            .foregroundStyle(.green.opacity(0.7))
                    }
                    .id(currentCommandIndex)
                    .contentTransition(.opacity)
                    .adaptiveAnimation(.easeInOut(duration: 0.4), reduced: .linear(duration: 0.25), value: currentCommandIndex)
                    .padding(Constants.spacingCard)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.85))
                    )

                    Button {
                        openSettings()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            NotificationCenter.default.post(name: SettingsView.openCLITabNotification, object: nil)
                        }
                    } label: {
                        Text("Install CLI")
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                }
            }
            .padding(Constants.spacingTight)
        }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            guard !reduceMotion else { return }
            currentCommandIndex = (currentCommandIndex + 1) % Self.cliCommands.count
        }
    }

    // MARK: - Helpers

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

    /// Determines whether an x-axis label should be shown for the current period.
    private func shouldShowXAxisLabel(_ label: String) -> Bool {
        switch selectedPeriod {
        case .daily:
            // Show 3am, 6am, 9am, 12pm, 3pm, 6pm, 9pm
            let visibleHours: Set<String> = [
                hourLabel(3), hourLabel(6), hourLabel(9), hourLabel(12),
                hourLabel(15), hourLabel(18), hourLabel(21),
            ]
            return visibleHours.contains(label)
        case .weekly:
            return true
        case .monthly:
            // Show 1, 7, 14, 21, 28 (skip 28 for 29-day months), and the last day
            let daysInMonth = allDayNumberLabels.count
            var visible: Set<String> = ["1", "7", "14", "21"]
            if daysInMonth != 29 {
                visible.insert("28")
            }
            let lastDay = String(daysInMonth)
            visible.insert(lastDay)
            return visible.contains(label)
        }
    }

    /// Format a value for tooltip display, using the correct unit for the period.
    private func formatValue(_ value: Double) -> String {
        if selectedPeriod == .daily {
            // Value is in minutes
            TimeFormatting.formatDuration(seconds: Int(value * 60))
        } else {
            // Value is in hours
            TimeFormatting.formatDuration(seconds: Int(value * 3600))
        }
    }

    // MARK: - Data Loading

    private func resetHoverState() {
        hoveredBarLabel = nil
        activityAngleSelection = nil
        hoveredActivityName = nil
        legendHoveredActivity = nil
        hoveredTagName = nil
        externalIdAngleSelection = nil
        hoveredExternalSegment = nil
    }

    /// When drilling down to a smaller period, return the earliest date with activity.
    private func drillDownDate(from oldPeriod: ReportPeriod, to newPeriod: ReportPeriod) -> Date? {
        switch (oldPeriod, newPeriod) {
        case (.monthly, .weekly):
            return monthlySummaryData?.weeklyBreakdown
                .first(where: { $0.sessionCount > 0 })?.weekOf
        case (.monthly, .daily):
            return monthlySummaryData?.dailyBreakdown
                .first(where: { $0.sessionCount > 0 })?.date
        case (.weekly, .daily):
            return weeklySummaryData?.dailyBreakdown
                .first(where: { $0.sessionCount > 0 })?.date
        default:
            return nil
        }
    }

    private func reloadReport() {
        loadTask?.cancel()
        resetHoverState()
        // Clear stale summary data so computed chart properties don't mix periods
        dailySummaryData = nil
        weeklySummaryData = nil
        monthlySummaryData = nil
        activities = []
        totalSeconds = 0
        sessionCount = 0
        tagActivitySummaries = []
        sessionEntries = []
        loadTask = Task { await loadReport() }
    }

    private func loadInitialState() async {
        do {
            earliestDate = try await appState.service.earliestSessionDate()
        } catch {
            appState.showError(error, context: "Could not load report data")
        }
    }

    private func loadReport() async {
        do {
            // Re-read week start preference on every load (store locally until data is ready)
            var effectiveWeekStartDay = weekStartDay
            if let weekStartPref = try await appState.service.getPreference(key: PreferenceKey.weekStartDay) {
                effectiveWeekStartDay = PreferenceKey.parseWeekStartDay(weekStartPref)
            }

            // Bail out if this task was cancelled (user switched periods/dates)
            try Task.checkCancellation()

            var calendar = Calendar.current
            calendar.firstWeekday = effectiveWeekStartDay

            switch selectedPeriod {
            case .daily:
                let summary = try await appState.service.dailySummary(date: selectedDate, includeArchived: !hideArchived)
                let startOfDay = calendar.startOfDay(for: selectedDate)
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? selectedDate
                let tags = try await appState.service.tagActivitySummary(from: startOfDay, to: endOfDay, includeArchived: !hideArchived)
                try Task.checkCancellation()
                // Batch all state updates together to avoid mid-render inconsistencies
                let sessions = try await appState.service.listSessions(from: startOfDay, to: endOfDay, type: nil, activityId: nil, includeArchived: !hideArchived)
                try Task.checkCancellation()
                weekStartDay = effectiveWeekStartDay
                dailySummaryData = summary
                activities = summary.activities
                totalSeconds = summary.totalSeconds
                sessionCount = summary.sessionCount
                tagActivitySummaries = tags
                sessionEntries = sessions

            case .weekly:
                let summary = try await appState.service.weeklySummary(weekOf: selectedDate, includeArchived: !hideArchived, weekStartDay: effectiveWeekStartDay)
                let wStart = weekStart(for: selectedDate)
                let weekEnd = calendar.date(byAdding: .day, value: 7, to: wStart) ?? selectedDate
                let tags = try await appState.service.tagActivitySummary(from: wStart, to: weekEnd, includeArchived: !hideArchived)
                try Task.checkCancellation()
                let sessions = try await appState.service.listSessions(from: wStart, to: weekEnd, type: nil, activityId: nil, includeArchived: !hideArchived)
                try Task.checkCancellation()
                weekStartDay = effectiveWeekStartDay
                weeklySummaryData = summary
                activities = summary.activities
                totalSeconds = summary.totalSeconds
                sessionCount = summary.sessionCount
                tagActivitySummaries = tags
                sessionEntries = sessions

            case .monthly:
                let summary = try await appState.service.monthlySummary(monthOf: selectedDate, includeArchived: !hideArchived, weekStartDay: effectiveWeekStartDay)
                guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate) else { return }
                let tags = try await appState.service.tagActivitySummary(from: monthInterval.start, to: monthInterval.end, includeArchived: !hideArchived)
                try Task.checkCancellation()
                let sessions = try await appState.service.listSessions(from: monthInterval.start, to: monthInterval.end, type: nil, activityId: nil, includeArchived: !hideArchived)
                try Task.checkCancellation()
                weekStartDay = effectiveWeekStartDay
                monthlySummaryData = summary
                activities = summary.activities
                totalSeconds = summary.totalSeconds
                sessionCount = summary.sessionCount
                tagActivitySummaries = tags
                sessionEntries = sessions
            }
        } catch is CancellationError {
            // Task was cancelled because user switched periods/dates — ignore
        } catch {
            appState.showError(error, context: "Could not load report")
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

private struct TagBarEntry: Identifiable {
    let id = UUID()
    let tagName: String
    let tagLabel: String
    let activityTitle: String
    let hours: Double
    let totalSeconds: Int
}
