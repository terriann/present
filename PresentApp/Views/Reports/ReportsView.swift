import SwiftUI
import PresentCore

struct ReportsView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var selectedPeriod: ReportPeriod = .daily
    @State private var selectedDate: Date = Date()
    @State private var activities: [ActivitySummary] = []
    @State private var totalSeconds: Int = 0
    @State private var sessionCount: Int = 0
    @State private var dailySummaryData: DailySummary?
    @State private var weeklySummaryData: WeeklySummary?
    @State private var monthlySummaryData: MonthlySummary?
    @State private var tagActivitySummaries: [TagActivitySummary] = []
    @State private var externalIdSummaries: [ExternalIdSummary] = []
    @State private var sessionEntries: [(Session, Activity)] = []
    @State private var sessionSegments: [Int64: [SessionSegment]] = [:]

    @State private var activeActivityTags: [Tag] = []

    // Navigation state
    @State private var showDatePicker = false
    @State private var earliestDate: Date?
    @State private var weekStartDay: Int = 1 // Calendar.firstWeekday: 1=Sunday, 2=Monday
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: Constants.spacingPage) {
                controlsBar
                periodNavigationBar
                summaryBar

                if !activities.isEmpty || (isShowingToday && appState.isSessionActive) {
                    if selectedPeriod == .daily {
                        ReportDayTimelineCard(
                            sessionEntries: sessionEntries,
                            sessionSegments: sessionSegments,
                            activityColorMap: activityColorMap,
                            referenceDate: Calendar.current.startOfDay(for: selectedDate)
                        )
                    }
                    ReportStackedBarChart(
                        entries: barEntries,
                        domain: xAxisDomain,
                        tooltipLabels: weeklyTooltipLabelMap,
                        selectedPeriod: selectedPeriod,
                        activities: activities,
                        chartColorDomain: chartColorDomain,
                        chartColorRange: chartColorRange,
                        activityColorMap: activityColorMap,
                        weekendDayLabels: weekendDayLabels
                    )
                    HStack(alignment: .top, spacing: Constants.spacingToolbar) {
                        ReportActivityPieChart(
                            activities: displayActivities,
                            totalSeconds: displayTotalSeconds,
                            chartColorDomain: chartColorDomain,
                            chartColorRange: chartColorRange,
                            activityColorMap: activityColorMap,
                            activeActivityTitle: activeActivityTitle
                        )
                        .frame(maxWidth: .infinity)
                        if !displayTagActivitySummaries.isEmpty {
                            ReportTagBarChart(
                                tagActivitySummaries: displayTagActivitySummaries,
                                activities: displayActivities,
                                chartColorDomain: chartColorDomain,
                                chartColorRange: chartColorRange,
                                activityColorMap: activityColorMap,
                                activeTagNames: activeTagNames
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    ReportExternalIdChart(
                        groups: displayExternalIdSummaries,
                        activeExternalId: activeExternalId
                    )
                } else {
                    GroupBox {
                        ContentUnavailableView(
                            "No Data",
                            systemImage: "chart.pie",
                            description: Text("No sessions recorded for this period.")
                        )
                        .emptyStateStyle()
                    }
                }

                ActivitySessionCard(
                    title: "Session Logs",
                    sessionEntries: sessionEntries,
                    activityColorMap: activityColorMap,
                    includeActiveSession: shouldIncludeActive,
                    timeReferenceDate: selectedPeriod == .daily ? Calendar.current.startOfDay(for: selectedDate) : nil,
                    resetToken: [selectedDate.description, selectedPeriod.rawValue] as [AnyHashable],
                    onReload: { reloadReport(clearData: false) }
                )
                ReportCLIPromoCard()
            }
            .padding(Constants.spacingPage)
        }
        .navigationTitle("Reports")
        .task {
            await loadInitialState()
            loadActiveActivityTags()
            await loadReport()
        }
        .onChange(of: selectedPeriod) { oldPeriod, newPeriod in
            showDatePicker = false
            if let target = drillDownDate(from: oldPeriod, to: newPeriod), target != selectedDate {
                selectedDate = target  // onChange(of: selectedDate) will trigger reload
                return
            }
            reloadReport()
        }
        .onChange(of: selectedDate) {
            reloadReport()
        }
        .onChange(of: appState.isSessionActive) {
            loadActiveActivityTags()
        }
    }

    // MARK: - Controls

    private var controlsBar: some View {
        Picker("Report period", selection: $selectedPeriod) {
            ForEach(ReportPeriod.allCases, id: \.self) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Period Navigation

    private var periodNavigationBar: some View {
        HStack(spacing: Constants.spacingCompact) {
            Button {
                navigatePeriod(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .disabled(!canNavigateBack)
            .buttonStyle(.borderless)
            .accessibilityLabel("Previous \(selectedPeriod.rawValue.lowercased()) period")
            .help("Previous \(selectedPeriod.rawValue.lowercased()) period")

            Button {
                showDatePicker.toggle()
            } label: {
                HStack(spacing: Constants.spacingTight) {
                    Text(periodHeaderText)
                        .font(.periodHeader)
                    Image(systemName: "chevron.down")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(periodHeaderText). Open date picker")
            .accessibilityAddTraits(.isHeader)
            .popover(isPresented: $showDatePicker) {
                ReportDatePickerPopover(
                    selectedDate: $selectedDate,
                    selectedPeriod: selectedPeriod,
                    weekStartDay: weekStartDay,
                    earliestDate: earliestDate,
                    dismiss: { showDatePicker = false }
                )
            }

            Button {
                navigatePeriod(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .disabled(!canNavigateForward)
            .buttonStyle(.borderless)
            .accessibilityLabel("Next \(selectedPeriod.rawValue.lowercased()) period")
            .help("Next \(selectedPeriod.rawValue.lowercased()) period")

            Spacer()
        }
    }

    private var periodHeaderText: String {
        let calendar = Calendar.current
        switch selectedPeriod {
        case .daily:
            return ChartFormatters.fullDate.string(from: selectedDate)
        case .weekly:
            let weekStart = weekStart(for: selectedDate)
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            return TimeFormatting.formatWeekRange(start: weekStart, end: weekEnd)
        case .monthly:
            return ChartFormatters.monthYear.string(from: selectedDate)
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

    // MARK: - Active Session

    /// Whether to include the active session's elapsed time in charts and stats.
    private var shouldIncludeActive: Bool {
        isShowingToday && appState.isSessionActive
    }

    /// The activity for the currently running session, when inclusion is enabled.
    private var activeActivity: Activity? {
        shouldIncludeActive ? appState.currentActivity : nil
    }

    /// Elapsed seconds for the active session, clamped to today's portion for cross-midnight sessions.
    /// Mirrors `DashboardView.todayPortionSeconds`.
    private var activeElapsedSeconds: Int {
        guard shouldIncludeActive, let session = appState.currentSession else { return 0 }
        let elapsed = appState.timerElapsedSeconds
        if Calendar.current.isDateInToday(session.startedAt) {
            return TimeFormatting.floorToMinute(elapsed)
        }
        let secondsSinceMidnight = Int(Date().timeIntervalSince(Calendar.current.startOfDay(for: Date())))
        return TimeFormatting.floorToMinute(min(elapsed, secondsSinceMidnight))
    }

    private var displayTotalSeconds: Int {
        totalSeconds + activeElapsedSeconds
    }

    private var displaySessionCount: Int {
        sessionCount + (shouldIncludeActive ? 1 : 0)
    }

    private var displayActivityCount: Int {
        var count = activities.count
        if let activity = activeActivity,
           !activities.contains(where: { $0.activity.id == activity.id }) {
            count += 1
        }
        return count
    }

    /// Activities augmented with the active session's elapsed time (for pie chart, external ID chart).
    private var displayActivities: [ActivitySummary] {
        guard let activity = activeActivity, !activity.isSystem else { return activities }
        var result = activities
        if let index = result.firstIndex(where: { $0.activity.id == activity.id }) {
            result[index].totalSeconds += activeElapsedSeconds
            result[index].sessionCount += 1
        } else {
            result.append(ActivitySummary(
                activity: activity,
                totalSeconds: activeElapsedSeconds,
                sessionCount: 1
            ))
        }
        return result
    }

    /// Tag summaries augmented with the active session's elapsed time.
    private var displayTagActivitySummaries: [TagActivitySummary] {
        guard let activity = activeActivity, !activity.isSystem else { return tagActivitySummaries }
        var result = tagActivitySummaries
        let tagNames = Set(activeActivityTags.map(\.name))

        for tagName in tagNames {
            if let tagIndex = result.firstIndex(where: { $0.tagName == tagName }) {
                // Tag exists — inject active time into matching activity or add new entry
                if let actIndex = result[tagIndex].activities.firstIndex(where: { $0.activity.id == activity.id }) {
                    result[tagIndex].activities[actIndex].totalSeconds += activeElapsedSeconds
                    result[tagIndex].activities[actIndex].sessionCount += 1
                } else {
                    result[tagIndex].activities.append(ActivitySummary(
                        activity: activity, totalSeconds: activeElapsedSeconds, sessionCount: 1
                    ))
                    result[tagIndex].activityCount += 1
                }
                result[tagIndex].totalSeconds += activeElapsedSeconds
            } else {
                // New tag entry
                result.append(TagActivitySummary(
                    tagName: tagName,
                    activities: [ActivitySummary(
                        activity: activity, totalSeconds: activeElapsedSeconds, sessionCount: 1
                    )],
                    totalSeconds: activeElapsedSeconds,
                    activityCount: 1
                ))
            }
        }
        return result
    }

    /// External ID summaries augmented with the active session's elapsed time.
    private var displayExternalIdSummaries: [ExternalIdSummary] {
        guard let activity = activeActivity, !activity.isSystem else { return externalIdSummaries }
        guard let effectiveId = activeExternalId else { return externalIdSummaries }
        var result = externalIdSummaries
        let activityName = activeActivity?.title ?? ""
        if let index = result.firstIndex(where: { $0.externalId == effectiveId }) {
            result[index].totalSeconds += activeElapsedSeconds
            result[index].sessionCount += 1
            if !result[index].activityNames.contains(activityName) {
                result[index].activityNames.append(activityName)
            }
        } else {
            result.append(ExternalIdSummary(
                externalId: effectiveId,
                totalSeconds: activeElapsedSeconds,
                sessionCount: 1,
                activityNames: [activityName]
            ))
        }
        return result
    }

    /// The title of the active activity (for charts to identify which element to pulse).
    private var activeActivityTitle: String? {
        guard let activity = activeActivity, !activity.isSystem else { return nil }
        return activity.title
    }

    /// Tag names that include active session data (for tag chart pulsing).
    private var activeTagNames: Set<String> {
        guard activeActivity != nil else { return [] }
        return Set(activeActivityTags.map(\.name))
    }

    /// The effective external ID for the active session (session ticket ID wins over activity external ID).
    private var activeExternalId: String? {
        guard activeActivity != nil else { return nil }
        return appState.currentSession?.ticketId ?? activeActivity?.externalId
    }

    private func loadActiveActivityTags() {
        guard let activity = appState.currentActivity, let id = activity.id else {
            activeActivityTags = []
            return
        }
        Task {
            do {
                activeActivityTags = try await appState.tagsForActivity(activityId: id)
            } catch {
                activeActivityTags = []
            }
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 40) {
            StatItem(
                title: "Total Time",
                value: TimeFormatting.formatDuration(seconds: displayTotalSeconds)
            )

            StatItem(
                title: "Sessions",
                value: "\(displaySessionCount)"
            )

            StatItem(
                title: "Activities",
                value: "\(displayActivityCount)"
            )

            Spacer()
        }
    }

    // MARK: - Chart Colors

    private var chartColorDomain: [String] {
        var titles = Set(activities.map(\.activity.title))
        // Include active activity so chart color scale covers it when injected into entries.
        if let activity = activeActivity {
            titles.insert(activity.title)
        }
        // Include any activity that appears in bar entries — dailyBreakdown can contain
        // activities not present in the top-level summary (e.g. cross-week boundaries).
        // Without this, chartForegroundStyleScale crashes on an unknown domain value.
        for entry in barEntries {
            titles.insert(entry.activity)
        }
        // Include activities from tag summaries — tagActivitySummary is a separate
        // service call that can return activities absent from the period summary
        // (e.g. monthly summary aggregates weekly boundaries differently).
        for tag in displayTagActivitySummaries {
            for summary in tag.activities {
                titles.insert(summary.activity.title)
            }
        }
        return titles.sorted()
    }

    private var chartColorRange: [Color] {
        let palette = ThemeManager.chartColors(for: theme.activePalette)
        return chartColorDomain.indices.map { palette[$0 % palette.count] }
    }

    private var activityColorMap: [String: Color] {
        Dictionary(uniqueKeysWithValues: zip(chartColorDomain, chartColorRange))
    }

    // MARK: - Bar Entry Data

    private var barEntries: [BarEntry] {
        var entries: [BarEntry]
        switch selectedPeriod {
        case .daily:
            let buckets = dailySummaryData?.hourlyBreakdown ?? []
            entries = buckets.map { bucket in
                BarEntry(
                    label: hourLabel(bucket.hour),
                    activity: bucket.activity.title,
                    value: Double(bucket.totalSeconds) / 60.0
                )
            }
        case .weekly:
            let dailyBreakdown = weeklySummaryData?.dailyBreakdown ?? []
            entries = dailyBreakdown.flatMap { daily in
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
            entries = dailyBreakdown.flatMap { daily in
                daily.activities.map { summary in
                    BarEntry(
                        label: dayNumberLabel(daily.date),
                        activity: summary.activity.title,
                        value: Double(summary.totalSeconds) / 3600.0
                    )
                }
            }
        }

        // Inject active session into the correct bucket (mirrors DashboardWeeklyChartCard pattern).
        // Skip system activities (e.g., Break).
        if let activity = activeActivity, !activity.isSystem {
            let activeLabel: String
            let activeValue: Double
            switch selectedPeriod {
            case .daily:
                activeLabel = hourLabel(Calendar.current.component(.hour, from: Date()))
                activeValue = Double(activeElapsedSeconds) / 60.0
            case .weekly:
                activeLabel = dayLabel(Date())
                activeValue = Double(activeElapsedSeconds) / 3600.0
            case .monthly:
                activeLabel = dayNumberLabel(Date())
                activeValue = Double(activeElapsedSeconds) / 3600.0
            }

            if let index = entries.firstIndex(where: { $0.label == activeLabel && $0.activity == activity.title }) {
                let existing = entries[index]
                entries[index] = BarEntry(
                    label: existing.label, activity: existing.activity,
                    value: existing.value + activeValue, isActive: true
                )
            } else {
                entries.append(BarEntry(
                    label: activeLabel, activity: activity.title,
                    value: activeValue, isActive: true
                ))
            }
        }

        // During async reload transitions, selectedDate (which drives xAxisDomain) may
        // advance while summary data is stale from the previous period. Filter out entries
        // whose labels fall outside the current domain to prevent Swift Charts from asserting
        // on out-of-domain x-values in .chartXScale(domain:). See #275.
        let validLabels = Set(xAxisDomain)
        return entries.filter { validLabels.contains($0.label) }
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
        let start = weekStart(for: selectedDate)
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return ChartFormatters.weekday.string(from: date)
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
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return ChartFormatters.hour.string(from: date).lowercased()
    }

    private func dayLabel(_ date: Date) -> String {
        ChartFormatters.weekday.string(from: date)
    }

    private func dayNumberLabel(_ date: Date) -> String {
        ChartFormatters.dayNumber.string(from: date)
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

    /// Reload report data.
    ///
    /// - Parameter clearData: When `true` (default), clears all summary and chart data
    ///   before loading to prevent mixing stale values across period/date changes. Pass
    ///   `false` for in-place refreshes (e.g. after a session edit) so existing content
    ///   stays visible and the ScrollView doesn't reset to the top.
    private func reloadReport(clearData: Bool = false) {
        loadTask?.cancel()
        if clearData {
            dailySummaryData = nil
            weeklySummaryData = nil
            monthlySummaryData = nil
            activities = []
            totalSeconds = 0
            sessionCount = 0
            tagActivitySummaries = []
            externalIdSummaries = []
            sessionEntries = []
            sessionSegments = [:]
        }
        loadTask = Task { await loadReport() }
    }

    private func loadInitialState() async {
        do {
            earliestDate = try await appState.earliestSessionDate()
        } catch is CancellationError {
            // Task cancelled by SwiftUI lifecycle — expected, not an error.
        } catch {
            appState.showError(error, context: "Could not load report data")
        }
    }

    private func loadReport() async {
        do {
            // Re-read week start preference on every load (store locally until data is ready)
            var effectiveWeekStartDay = weekStartDay
            if let weekStartPref = try await appState.getPreference(key: PreferenceKey.weekStartDay) {
                effectiveWeekStartDay = PreferenceKey.parseWeekStartDay(weekStartPref)
            }

            // Bail out if this task was cancelled (user switched periods/dates)
            try Task.checkCancellation()

            var calendar = Calendar.current
            calendar.firstWeekday = effectiveWeekStartDay

            switch selectedPeriod {
            case .daily:
                let summary = try await appState.dailySummary(date: selectedDate, includeArchived: true, roundToMinute: true)
                let startOfDay = calendar.startOfDay(for: selectedDate)
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? selectedDate
                let tags = try await appState.tagActivitySummary(from: startOfDay, to: endOfDay, includeArchived: true, roundToMinute: true)
                let extIds = try await appState.externalIdSummary(from: startOfDay, to: endOfDay, includeArchived: true)
                try Task.checkCancellation()
                // Batch all state updates together to avoid mid-render inconsistencies
                let sessions = try await appState.listSessions(from: startOfDay, to: endOfDay, type: nil, activityId: nil, includeArchived: true)
                try Task.checkCancellation()
                var sessionIds = sessions.compactMap { $0.0.id }
                if let activeId = appState.currentSession?.id, !sessionIds.contains(activeId) {
                    sessionIds.append(activeId)
                }
                let segments = try await appState.segmentsForSessions(sessionIds: sessionIds)
                try Task.checkCancellation()
                withAdaptiveAnimation(.easeInOut(duration: 0.35)) {
                    weekStartDay = effectiveWeekStartDay
                    dailySummaryData = summary
                    activities = summary.activities
                    totalSeconds = summary.totalSeconds
                    sessionCount = summary.sessionCount
                    tagActivitySummaries = tags
                    externalIdSummaries = extIds
                    sessionEntries = sessions
                    sessionSegments = segments
                }

            case .weekly:
                let summary = try await appState.weeklySummary(weekOf: selectedDate, includeArchived: true, weekStartDay: effectiveWeekStartDay, roundToMinute: true)
                let wStart = weekStart(for: selectedDate)
                let weekEnd = calendar.date(byAdding: .day, value: 7, to: wStart) ?? selectedDate
                let tags = try await appState.tagActivitySummary(from: wStart, to: weekEnd, includeArchived: true, roundToMinute: true)
                let extIds = try await appState.externalIdSummary(from: wStart, to: weekEnd, includeArchived: true)
                try Task.checkCancellation()
                let sessions = try await appState.listSessions(from: wStart, to: weekEnd, type: nil, activityId: nil, includeArchived: true)
                try Task.checkCancellation()
                withAdaptiveAnimation(.easeInOut(duration: 0.35)) {
                    weekStartDay = effectiveWeekStartDay
                    weeklySummaryData = summary
                    activities = summary.activities
                    totalSeconds = summary.totalSeconds
                    sessionCount = summary.sessionCount
                    tagActivitySummaries = tags
                    externalIdSummaries = extIds
                    sessionEntries = sessions
                }

            case .monthly:
                let summary = try await appState.monthlySummary(monthOf: selectedDate, includeArchived: true, weekStartDay: effectiveWeekStartDay, roundToMinute: true)
                guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate) else { return }
                let tags = try await appState.tagActivitySummary(from: monthInterval.start, to: monthInterval.end, includeArchived: true, roundToMinute: true)
                let extIds = try await appState.externalIdSummary(from: monthInterval.start, to: monthInterval.end, includeArchived: true)
                try Task.checkCancellation()
                let sessions = try await appState.listSessions(from: monthInterval.start, to: monthInterval.end, type: nil, activityId: nil, includeArchived: true)
                try Task.checkCancellation()
                withAdaptiveAnimation(.easeInOut(duration: 0.35)) {
                    weekStartDay = effectiveWeekStartDay
                    monthlySummaryData = summary
                    activities = summary.activities
                    totalSeconds = summary.totalSeconds
                    sessionCount = summary.sessionCount
                    tagActivitySummaries = tags
                    externalIdSummaries = extIds
                    sessionEntries = sessions
                }
            }
        } catch is CancellationError {
            // Task was cancelled because user switched periods/dates — ignore
        } catch {
            appState.showError(error, context: "Could not load report")
        }
    }
}
