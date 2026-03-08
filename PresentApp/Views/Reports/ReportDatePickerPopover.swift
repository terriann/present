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
    let isShowingToday: Bool
    let dismiss: () -> Void

    // Monthly picker state
    @State private var pickerYear: Int = Calendar.current.component(.year, from: Date())
    // Dates with recorded session data (for calendar dot indicators)
    @State private var datesWithData: Set<Date> = []

    var body: some View {
        VStack(spacing: Constants.spacingCard) {
            switch selectedPeriod {
            case .daily, .weekly:
                calendarPicker
            case .monthly:
                monthGridPicker
            }

            quickJumpButton
        }
        .padding(Constants.spacingCard)
        .frame(width: 320)
        .background(.regularMaterial)
        .onAppear {
            pickerYear = Calendar.current.component(.year, from: selectedDate)
        }
        .task {
            await loadDatesWithData()
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
            onDateSelected: { _ in dismiss() }
        )
    }

    // MARK: - Month Grid Picker (Monthly)

    private var monthGridPicker: some View {
        VStack(spacing: Constants.spacingCard) {
            yearNavigation
            monthGrid
        }
    }

    private var yearNavigation: some View {
        HStack {
            Button {
                pickerYear -= 1
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(!canNavigateYearBack)

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
            .disabled(!canNavigateYearForward)
        }
    }

    private var canNavigateYearBack: Bool {
        guard let earliest = earliestDate else { return true }
        return pickerYear > Calendar.current.component(.year, from: earliest)
    }

    private var canNavigateYearForward: Bool {
        pickerYear < Calendar.current.component(.year, from: Date())
    }

    private var monthGrid: some View {
        let columns = Array(repeating: GridItem(.flexible()), count: 3)
        return LazyVGrid(columns: columns, spacing: Constants.spacingCompact) {
            ForEach(1...12, id: \.self) { month in
                monthButton(month: month)
            }
        }
    }

    @ViewBuilder
    private func monthButton(month: Int) -> some View {
        let isSelected = isSelectedMonth(month)
        let isCurrent = isCurrentMonth(month)
        let enabled = isMonthEnabled(month)

        Button {
            selectMonth(month)
        } label: {
            Text(monthAbbreviation(month))
                .font(.callout)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Constants.spacingCompact)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? theme.accent.opacity(0.15) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isCurrent ? theme.accent : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? (isSelected ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.primary)) : AnyShapeStyle(.tertiary))
        .disabled(!enabled)
    }

    private func isSelectedMonth(_ month: Int) -> Bool {
        let calendar = Calendar.current
        return calendar.component(.year, from: selectedDate) == pickerYear
            && calendar.component(.month, from: selectedDate) == month
    }

    private func isCurrentMonth(_ month: Int) -> Bool {
        let now = Date()
        let calendar = Calendar.current
        return calendar.component(.year, from: now) == pickerYear
            && calendar.component(.month, from: now) == month
    }

    private func isMonthEnabled(_ month: Int) -> Bool {
        let calendar = Calendar.current
        // Disable future months
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        if pickerYear > currentYear || (pickerYear == currentYear && month > currentMonth) {
            return false
        }
        // Disable months before earliest date
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
            selectedDate = date
            dismiss()
        }
    }

    private func monthAbbreviation(_ month: Int) -> String {
        Calendar.current.shortMonthSymbols[month - 1]
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
        .disabled(isShowingToday)
    }

    // MARK: - Data Loading

    /// Load dates that have session data. Only fetches the visible month range
    /// (plus adjacent-month padding) to stay fast regardless of total history.
    private func loadDatesWithData() async {
        let calendar = Calendar.current
        // Load ~6 weeks around the selected date to cover the visible grid
        guard let rangeStart = calendar.date(byAdding: .day, value: -7, to: calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate),
              let rangeEnd = calendar.date(byAdding: .day, value: 7, to: calendar.dateInterval(of: .month, for: selectedDate)?.end ?? selectedDate) else {
            return
        }
        do {
            let sessions = try await appState.listSessions(from: rangeStart, to: rangeEnd, includeArchived: true)
            let dates = Set(sessions.map { calendar.startOfDay(for: $0.0.startedAt) })
            datesWithData = dates
        } catch {
            // Non-critical — dots just won't show
        }
    }
}
