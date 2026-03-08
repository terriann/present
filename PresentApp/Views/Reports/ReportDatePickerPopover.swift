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
    // Months with recorded session data (year-month pairs as "YYYY-MM")
    @State private var monthsWithData: Set<String> = []

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

    private let monthCellHeight: CGFloat = 32

    @ViewBuilder
    private func monthButton(month: Int) -> some View {
        let isSelected = isSelectedMonth(month)
        let isCurrent = isCurrentMonth(month)
        let enabled = isMonthEnabled(month)
        let hasData = monthHasData(month)

        Button {
            selectMonth(month)
        } label: {
            VStack(spacing: 4) {
                Text(monthAbbreviation(month))
                    .font(.callout)
                    .frame(maxWidth: .infinity)
                    .frame(height: monthCellHeight)
                    .background(
                        Capsule()
                            .fill(isSelected ? theme.accent.opacity(0.12) : Color.clear)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(isCurrent ? theme.accent : Color.clear, lineWidth: 1.5)
                    )

                Circle()
                    .fill(monthDotColor(isSelected: isSelected, enabled: enabled))
                    .frame(width: 5, height: 5)
                    .opacity(hasData ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? (isSelected ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.primary)) : AnyShapeStyle(.tertiary))
        .disabled(!enabled)
    }

    private func monthHasData(_ month: Int) -> Bool {
        let key = String(format: "%04d-%02d", pickerYear, month)
        return monthsWithData.contains(key)
    }

    private func monthDotColor(isSelected: Bool, enabled: Bool) -> Color {
        if isSelected { return theme.accent }
        return enabled ? theme.accent.opacity(0.5) : theme.accent.opacity(0.15)
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

    /// Load dates that have session data. Scoped to the visible range for the current period mode.
    private func loadDatesWithData() async {
        let calendar = Calendar.current
        do {
            if selectedPeriod == .monthly {
                // Load the full displayed year for monthly mode
                var startComponents = DateComponents()
                startComponents.year = pickerYear
                startComponents.month = 1
                startComponents.day = 1
                var endComponents = DateComponents()
                endComponents.year = pickerYear + 1
                endComponents.month = 1
                endComponents.day = 1
                guard let rangeStart = calendar.date(from: startComponents),
                      let rangeEnd = calendar.date(from: endComponents) else { return }

                let sessions = try await appState.listSessions(from: rangeStart, to: rangeEnd, includeArchived: true)
                let months = Set(sessions.map { session in
                    let date = session.0.startedAt
                    let year = calendar.component(.year, from: date)
                    let month = calendar.component(.month, from: date)
                    return String(format: "%04d-%02d", year, month)
                })
                monthsWithData = months
            } else {
                // Load ~6 weeks around the selected date to cover the visible grid
                guard let rangeStart = calendar.date(byAdding: .day, value: -7, to: calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate),
                      let rangeEnd = calendar.date(byAdding: .day, value: 7, to: calendar.dateInterval(of: .month, for: selectedDate)?.end ?? selectedDate) else { return }

                let sessions = try await appState.listSessions(from: rangeStart, to: rangeEnd, includeArchived: true)
                let dates = Set(sessions.map { calendar.startOfDay(for: $0.0.startedAt) })
                datesWithData = dates
            }
        } catch {
            // Non-critical — dots just won't show
        }
    }
}
