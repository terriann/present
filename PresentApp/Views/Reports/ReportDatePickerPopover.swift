import SwiftUI
import PresentCore

/// A context-aware date picker popover that adapts to the active report period.
///
/// - **Daily/Weekly**: Shows a custom month calendar grid (see `ReportCalendarGrid`).
/// - **Monthly**: Shows year navigation arrows with a 3×4 month button grid.
///
/// Includes a quick-jump button ("Today" / "This Week" / "This Month") at the bottom.
struct ReportDatePickerPopover: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    @Binding var selectedDate: Date
    let selectedPeriod: ReportPeriod
    let weekStartDay: Int
    let earliestDate: Date?
    let dismiss: () -> Void

    // Dates with recorded session data (for calendar dot indicators)
    @State private var datesWithData: Set<Date> = []
    // Months with recorded session data (year-month pairs as "YYYY-MM")
    @State private var monthsWithData: Set<String> = []
    // Tracks in-flight data loading task for cancellation on rapid navigation
    @State private var loadingTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: Constants.spacingCard) {
            switch selectedPeriod {
            case .daily, .weekly:
                calendarPicker
            case .monthly:
                ReportMonthPicker(
                    selectedDate: selectedDate,
                    earliestDate: earliestDate,
                    monthsWithData: monthsWithData,
                    onSelect: { date in
                        selectedDate = date
                        dismiss()
                    }
                )
            }

            quickJumpButton
        }
        .padding(Constants.spacingCard)
        .frame(width: 320)
        .background(.regularMaterial)
        .task {
            await loadDatesWithData()
        }
        .onDisappear {
            loadingTask?.cancel()
            loadingTask = nil
        }
    }

    // MARK: - Calendar Picker (Daily/Weekly)

    private var calendarPicker: some View {
        ReportCalendarGrid(
            selectedDate: $selectedDate,
            selectionMode: selectedPeriod == .weekly ? .week : .day,
            weekStartDay: weekStartDay,
            earliestDate: earliestDate,
            datesWithData: datesWithData,
            onDateSelected: { _ in dismiss() },
            onMonthChanged: { month in
                // Cancel in-flight request and debounce rapid navigation
                loadingTask?.cancel()
                loadingTask = Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    await loadDatesWithData(for: month)
                }
            }
        )
    }

    // MARK: - Quick Jump

    private var quickJumpLabel: String {
        switch selectedPeriod {
        case .daily: "Today"
        case .weekly: "This Week"
        case .monthly: "This Month"
        }
    }

    private var quickJumpButton: some View {
        Button(quickJumpLabel) {
            selectedDate = Date()
            dismiss()
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.accent)
        .controlSize(.small)
    }

    // MARK: - Data Loading

    /// Load dates that have session data using lightweight queries (no joins, no hydration).
    /// - Parameter targetDate: The reference date for scoping the query (defaults to `selectedDate`).
    private func loadDatesWithData(for targetDate: Date? = nil) async {
        let referenceDate = targetDate ?? selectedDate
        let calendar = Calendar.current
        do {
            if selectedPeriod == .monthly {
                // Load a broad range for monthly mode — covers most user history.
                // Note: this branch only runs on initial appear (monthly mode shows a month
                // grid, not ReportCalendarGrid, so onMonthChanged never fires for it).
                let initialYear = calendar.component(.year, from: referenceDate)
                var startComponents = DateComponents()
                startComponents.year = initialYear - 5
                startComponents.month = 1
                startComponents.day = 1
                var endComponents = DateComponents()
                endComponents.year = initialYear + 1
                endComponents.month = 1
                endComponents.day = 1
                guard let rangeStart = calendar.date(from: startComponents),
                      let rangeEnd = calendar.date(from: endComponents) else { return }

                monthsWithData = try await appState.monthsWithSessions(from: rangeStart, to: rangeEnd)
            } else {
                // Load ~6 weeks around the reference date to cover the visible grid
                guard let rangeStart = calendar.date(byAdding: .day, value: -7, to: calendar.dateInterval(of: .month, for: referenceDate)?.start ?? referenceDate),
                      let rangeEnd = calendar.date(byAdding: .day, value: 7, to: calendar.dateInterval(of: .month, for: referenceDate)?.end ?? referenceDate) else { return }

                datesWithData = try await appState.datesWithSessions(from: rangeStart, to: rangeEnd)
            }
        } catch {
            // Non-critical — dots just won't show
        }
    }
}

// MARK: - Month Picker

/// Self-contained monthly picker with year navigation and 3×4 month grid.
///
/// Owns its own `pickerYear` state so that year navigation button actions
/// (which write to `pickerYear`) and grid cell modifiers (which read it)
/// are fully isolated from the parent's dependency graph, preventing
/// AttributeGraph cycles.
private struct ReportMonthPicker: View {
    @Environment(ThemeManager.self) private var theme

    let selectedDate: Date
    let earliestDate: Date?
    let monthsWithData: Set<String>
    let onSelect: (Date) -> Void

    @State private var pickerYear: Int

    init(selectedDate: Date, earliestDate: Date?, monthsWithData: Set<String>, onSelect: @escaping (Date) -> Void) {
        self.selectedDate = selectedDate
        self.earliestDate = earliestDate
        self.monthsWithData = monthsWithData
        self.onSelect = onSelect
        _pickerYear = State(initialValue: Calendar.current.component(.year, from: selectedDate))
    }

    var body: some View {
        VStack(spacing: Constants.spacingCard) {
            yearNavigation
            monthGrid
        }
        .id(pickerYear)
    }

    // MARK: - Year Navigation

    private var yearNavigation: some View {
        HStack {
            Button {
                pickerYear -= 1
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(!canGoBack)
            .accessibilityLabel("Previous year")
            .help("Previous year")

            Spacer()

            Text(String(pickerYear))
                .font(.headline)
                .monospacedDigit()

            Spacer()

            Button {
                pickerYear += 1
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(!canGoForward)
            .accessibilityLabel("Next year")
            .help("Next year")
        }
    }

    private var canGoBack: Bool {
        guard let earliest = earliestDate else { return true }
        return pickerYear > Calendar.current.component(.year, from: earliest)
    }

    private var canGoForward: Bool {
        pickerYear < Calendar.current.component(.year, from: Date())
    }

    // MARK: - Month Grid

    private static let columns = Array(repeating: GridItem(.flexible()), count: 3)
    private static let cellHeight: CGFloat = 32

    private var monthGrid: some View {
        LazyVGrid(columns: Self.columns, spacing: Constants.spacingCompact) {
            ForEach(1...12, id: \.self) { month in
                MonthCell(
                    month: month,
                    isSelected: isSelectedMonth(month),
                    isCurrent: isCurrentMonth(month),
                    enabled: isMonthEnabled(month),
                    hasData: monthsWithData.contains(String(format: "%04d-%02d", pickerYear, month)),
                    cellHeight: Self.cellHeight,
                    onSelect: { selectMonth(month) }
                )
            }
        }
    }

    // MARK: - Helpers

    private func isSelectedMonth(_ month: Int) -> Bool {
        let calendar = Calendar.current
        return calendar.component(.year, from: selectedDate) == pickerYear
            && calendar.component(.month, from: selectedDate) == month
    }

    private func isCurrentMonth(_ month: Int) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        return calendar.component(.year, from: now) == pickerYear
            && calendar.component(.month, from: now) == month
    }

    private func isMonthEnabled(_ month: Int) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        if pickerYear > currentYear || (pickerYear == currentYear && month > currentMonth) {
            return false
        }
        if let earliest = earliestDate {
            let earliestYear = calendar.component(.year, from: earliest)
            let earliestMonth = calendar.component(.month, from: earliest)
            if pickerYear < earliestYear || (pickerYear == earliestYear && month < earliestMonth) {
                return false
            }
        }
        return true
    }

    private func selectMonth(_ month: Int) {
        var components = DateComponents()
        components.year = pickerYear
        components.month = month
        components.day = 1
        if let date = Calendar.current.date(from: components) {
            onSelect(date)
        }
    }

}

// MARK: - Month Cell

/// Standalone view struct for each month cell in the picker grid.
///
/// Extracted from `ReportMonthPicker` so each cell gets its own isolated
/// dependency subgraph in SwiftUI's AttributeGraph, preventing cycle warnings
/// when `pickerYear` changes.
private struct MonthCell: View {
    @Environment(ThemeManager.self) private var theme

    let month: Int
    let isSelected: Bool
    let isCurrent: Bool
    let enabled: Bool
    let hasData: Bool
    let cellHeight: CGFloat
    let onSelect: () -> Void

    var body: some View {
        Button { onSelect() } label: {
            VStack(spacing: Constants.spacingTight) {
                Text(Calendar.current.shortMonthSymbols[month - 1])
                    .font(.callout)
                    .frame(maxWidth: .infinity)
                    .frame(height: cellHeight)
                    .background(
                        Capsule()
                            .fill(isSelected ? theme.accent.opacity(0.12) : Color.clear)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(isCurrent ? theme.accent : Color.clear, lineWidth: 1.5)
                    )

                Circle()
                    .fill(dotColor)
                    .frame(width: 5, height: 5)
                    .opacity(hasData ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? (isSelected ? theme.accent : .primary) : .secondary.opacity(0.5))
        .disabled(!enabled)
    }

    private var dotColor: Color {
        if isSelected { return theme.accent }
        return enabled ? theme.accent.opacity(0.5) : theme.accent.opacity(0.15)
    }
}
