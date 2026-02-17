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

    // Navigation state
    @State private var earliestDate: Date?
    @State private var weekStartDay: Int = 1 // Calendar.firstWeekday: 1=Sunday, 2=Monday

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
    @State private var hoveredTagLabel: String?
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
                }

                cliPromoCard
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
        .onChange(of: hideArchived) {
            Task { await loadReport() }
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

    private var stackedBarChartCard: some View {
        let entries = barEntries
        let domain = xAxisDomain

        return GroupBox {
            Text("Time by \(selectedPeriod.timeLabel)")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 12)

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
                    let plotFrame = geometry[proxy.plotAreaFrame]

                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let relativeX = location.x - plotFrame.origin.x
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
                        barTooltip(for: label, entries: entries)
                            .fixedSize()
                            .frame(maxWidth: 180, alignment: .leading)
                            .position(x: pos.x, y: pos.y)
                    }
                }
            }
            .chartLegend(position: .bottom, spacing: 12)
            .frame(height: 250)
            .padding(12)
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

    private func tagTooltip(for label: String, summaries: [TagActivitySummary]) -> some View {
        // Find the matching TagActivitySummary — label format is "TagName (N) · duration"
        let matching = summaries.first { tag in
            let duration = TimeFormatting.formatDuration(seconds: tag.totalSeconds)
            return "\(tag.tagName) · \(duration) (\(tag.activityCount))" == label
        }
        let palette = ThemeManager.chartColors(for: theme.activePalette)

        return ChartTooltip {
            if let tag = matching {
                Text(tag.tagName)
                    .font(.caption.bold())

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
                            .font(.caption.monospacedDigit())
                    }
                }

                if tag.activities.count > 1 {
                    Divider()
                    HStack {
                        Text("Total")
                            .font(.caption.bold())
                        Spacer()
                        Text(TimeFormatting.formatDuration(seconds: tag.totalSeconds))
                            .font(.caption.bold().monospacedDigit())
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

        return GroupBox {
            Text("External ID Breakdown")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 12)

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
                    let plotFrame = geometry[proxy.plotAreaFrame]
                    if let segmentId = hoveredExternalSegment,
                       let group = groups.first(where: { $0.externalId == segmentId }) {
                        donutCenterTooltip {
                            Text(group.externalId)
                                .font(.caption.bold())
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            Text(TimeFormatting.formatDuration(seconds: group.totalSeconds))
                                .font(.caption.monospacedDigit())
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
                            x: plotFrame.midX,
                            y: plotFrame.midY
                        )
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(height: 250)
            .padding(12)

            FlowLayout(spacing: 8) {
                ForEach(Array(groups.enumerated()), id: \.element.externalId) { index, group in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(palette[index % palette.count])
                            .frame(width: 8, height: 8)
                        Text(group.externalId)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(hoveredExternalSegment == group.externalId ? Color.primary.opacity(0.08) : Color.clear)
                    )
                    .onHover { hovering in
                        hoveredExternalSegment = hovering ? group.externalId : findExternalSegment(for: externalIdAngleSelection)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
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
        GroupBox {
            Text("Activity Distribution")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 12)

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
                    let plotFrame = geometry[proxy.plotAreaFrame]
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
                        .position(
                            x: plotFrame.midX,
                            y: plotFrame.midY
                        )
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(height: 250)
            .padding(12)

            donutLegend
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }

    private var donutLegend: some View {
        let palette = ThemeManager.chartColors(for: theme.activePalette)
        return FlowLayout(spacing: 8) {
            ForEach(Array(activities.enumerated()), id: \.element.activity.id) { index, summary in
                HStack(spacing: 4) {
                    Circle()
                        .fill(palette[index % palette.count])
                        .frame(width: 8, height: 8)
                    Text(summary.activity.title)
                        .font(.caption)
                        .lineLimit(1)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hoveredActivityName == summary.activity.title ? Color.primary.opacity(0.08) : Color.clear)
                )
                .onHover { hovering in
                    if hovering {
                        legendHoveredActivity = summary.activity.title
                        hoveredActivityName = summary.activity.title
                    } else {
                        legendHoveredActivity = nil
                        hoveredActivityName = findActivity(for: activityAngleSelection)
                    }
                }
            }
        }
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
                    tagLabel: yLabel,
                    activityTitle: summary.activity.title,
                    hours: Double(summary.totalSeconds) / 3600.0,
                    totalSeconds: tag.totalSeconds,
                    isLastInTag: false
                )
            }
        }

        return GroupBox {
            Text("Tag Distribution")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 12)

            Chart(entries, id: \.id) { entry in
                BarMark(
                    x: .value("Hours", entry.hours),
                    y: .value("Tag", entry.tagLabel)
                )
                .foregroundStyle(by: .value("Activity", entry.activityTitle))
                .opacity(hoveredTagLabel == nil || hoveredTagLabel == entry.tagLabel ? 1.0 : 0.4)
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
                    let plotFrame = geometry[proxy.plotAreaFrame]

                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let relativeY = location.y - plotFrame.origin.y
                                if let label: String = proxy.value(atY: relativeY) {
                                    hoveredTagLabel = label
                                    tagHoverLocation = location
                                } else {
                                    hoveredTagLabel = nil
                                }
                            case .ended:
                                hoveredTagLabel = nil
                            }
                        }

                    if let label = hoveredTagLabel {
                        let pos = tooltipPosition(cursor: tagHoverLocation, containerSize: geometry.size)
                        tagTooltip(for: label, summaries: sorted)
                            .fixedSize()
                            .frame(maxWidth: 200, alignment: .leading)
                            .position(x: pos.x, y: pos.y)
                    }
                }
            }
            .frame(height: barHeight)
            .padding(12)
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
                            .font(.system(.body, design: .monospaced))
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
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.green)
                        Text(pair.output)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.7))
                    }
                    .id(currentCommandIndex)
                    .contentTransition(.opacity)
                    .adaptiveAnimation(.easeInOut(duration: 0.4), reduced: .linear(duration: 0.25), value: currentCommandIndex)
                    .padding(12)
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
            .padding(4)
        }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            guard !reduceMotion else { return }
            currentCommandIndex = (currentCommandIndex + 1) % Self.cliCommands.count
        }
    }

    // MARK: - Helpers

    /// Calculates tooltip center position near the cursor, flipping sides and clamping to stay
    /// at least 1em (16pt) from each edge of the container.
    private func tooltipPosition(cursor: CGPoint, containerSize: CGSize) -> CGPoint {
        let tooltipWidth: CGFloat = 180
        let tooltipHeight: CGFloat = 100
        let edgePadding: CGFloat = 6
        let cursorOffset: CGFloat = 6

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
            var calendar = Calendar.current
            calendar.firstWeekday = effectiveWeekStartDay

            switch selectedPeriod {
            case .daily:
                let summary = try await appState.service.dailySummary(date: selectedDate, includeArchived: !hideArchived)
                let startOfDay = calendar.startOfDay(for: selectedDate)
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
                let tags = try await appState.service.tagActivitySummary(from: startOfDay, to: endOfDay, includeArchived: !hideArchived)
                // Batch all state updates together to avoid mid-render inconsistencies
                weekStartDay = effectiveWeekStartDay
                dailySummaryData = summary
                activities = summary.activities
                totalSeconds = summary.totalSeconds
                sessionCount = summary.sessionCount
                tagActivitySummaries = tags

            case .weekly:
                let summary = try await appState.service.weeklySummary(weekOf: selectedDate, includeArchived: !hideArchived)
                let wStart = weekStart(for: selectedDate)
                let weekEnd = calendar.date(byAdding: .day, value: 7, to: wStart)!
                let tags = try await appState.service.tagActivitySummary(from: wStart, to: weekEnd, includeArchived: !hideArchived)
                weekStartDay = effectiveWeekStartDay
                weeklySummaryData = summary
                activities = summary.activities
                totalSeconds = summary.totalSeconds
                sessionCount = summary.sessionCount
                tagActivitySummaries = tags

            case .monthly:
                let summary = try await appState.service.monthlySummary(monthOf: selectedDate, includeArchived: !hideArchived)
                let monthInterval = calendar.dateInterval(of: .month, for: selectedDate)!
                let tags = try await appState.service.tagActivitySummary(from: monthInterval.start, to: monthInterval.end, includeArchived: !hideArchived)
                weekStartDay = effectiveWeekStartDay
                monthlySummaryData = summary
                activities = summary.activities
                totalSeconds = summary.totalSeconds
                sessionCount = summary.sessionCount
                tagActivitySummaries = tags
            }
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
    let tagLabel: String
    let activityTitle: String
    let hours: Double
    let totalSeconds: Int
    let isLastInTag: Bool
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
