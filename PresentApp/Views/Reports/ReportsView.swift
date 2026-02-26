import SwiftUI
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
    @State private var sessionSegments: [Int64: [SessionSegment]] = [:]

    // Navigation state
    @State private var earliestDate: Date?
    @State private var weekStartDay: Int = 1 // Calendar.firstWeekday: 1=Sunday, 2=Monday
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                controlsBar
                periodNavigationBar
                summaryBar

                if !activities.isEmpty {
                    ReportStackedBarChart(
                        entries: barEntries,
                        domain: xAxisDomain,
                        tooltipLabels: weeklyTooltipLabelMap,
                        selectedPeriod: selectedPeriod,
                        activities: activities,
                        chartColorDomain: chartColorDomain,
                        chartColorRange: chartColorRange,
                        weekendDayLabels: weekendDayLabels
                    )
                    HStack(alignment: .top, spacing: 16) {
                        ReportActivityPieChart(
                            activities: activities,
                            totalSeconds: totalSeconds,
                            chartColorDomain: chartColorDomain,
                            chartColorRange: chartColorRange
                        )
                        .frame(maxWidth: .infinity)
                        if !tagActivitySummaries.isEmpty {
                            ReportTagBarChart(
                                tagActivitySummaries: tagActivitySummaries,
                                activities: activities,
                                chartColorDomain: chartColorDomain,
                                chartColorRange: chartColorRange
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    ReportExternalIdChart(activities: activities)
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

                ReportSessionLogCard(sessionEntries: sessionEntries, onReload: reloadReport)
                ReportCLIPromoCard()
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

    private var activityColorMap: [String: Color] {
        Dictionary(uniqueKeysWithValues: zip(chartColorDomain, chartColorRange))
    }

    // MARK: - Bar Entry Data

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

    private var weeklyTooltipLabelMap: [String: String] {
        guard selectedPeriod == .weekly else { return [:] }
        return weeklyTooltipLabels(weekStartDay: weekStartDay, referenceDate: selectedDate)
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

    // MARK: - Data Loading

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
        // Clear stale summary data so computed chart properties don't mix periods
        dailySummaryData = nil
        weeklySummaryData = nil
        monthlySummaryData = nil
        activities = []
        totalSeconds = 0
        sessionCount = 0
        tagActivitySummaries = []
        sessionEntries = []
        sessionSegments = [:]
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
                let summary = try await appState.service.dailySummary(date: selectedDate, includeArchived: !hideArchived, roundToMinute: true)
                let startOfDay = calendar.startOfDay(for: selectedDate)
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? selectedDate
                let tags = try await appState.service.tagActivitySummary(from: startOfDay, to: endOfDay, includeArchived: !hideArchived, roundToMinute: true)
                try Task.checkCancellation()
                // Batch all state updates together to avoid mid-render inconsistencies
                let sessions = try await appState.service.listSessions(from: startOfDay, to: endOfDay, type: nil, activityId: nil, includeArchived: !hideArchived)
                try Task.checkCancellation()
                let sessionIds = sessions.compactMap { $0.0.id }
                let segments = try await appState.service.segmentsForSessions(sessionIds: sessionIds)
                try Task.checkCancellation()
                weekStartDay = effectiveWeekStartDay
                dailySummaryData = summary
                activities = summary.activities
                totalSeconds = summary.totalSeconds
                sessionCount = summary.sessionCount
                tagActivitySummaries = tags
                sessionEntries = sessions
                sessionSegments = segments

            case .weekly:
                let summary = try await appState.service.weeklySummary(weekOf: selectedDate, includeArchived: !hideArchived, weekStartDay: effectiveWeekStartDay, roundToMinute: true)
                let wStart = weekStart(for: selectedDate)
                let weekEnd = calendar.date(byAdding: .day, value: 7, to: wStart) ?? selectedDate
                let tags = try await appState.service.tagActivitySummary(from: wStart, to: weekEnd, includeArchived: !hideArchived, roundToMinute: true)
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
                let summary = try await appState.service.monthlySummary(monthOf: selectedDate, includeArchived: !hideArchived, weekStartDay: effectiveWeekStartDay, roundToMinute: true)
                guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate) else { return }
                let tags = try await appState.service.tagActivitySummary(from: monthInterval.start, to: monthInterval.end, includeArchived: !hideArchived, roundToMinute: true)
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
