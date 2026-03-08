import SwiftUI
import PresentCore

/// Selection mode for the calendar grid.
enum CalendarSelectionMode {
    /// Select a single day (daily reports).
    case day
    /// Select an entire week row (weekly reports).
    case week
}

/// A custom month calendar grid inspired by Mijick/CalendarView.
///
/// Renders a full month with weekday headers, month/year navigation, and two selection modes:
/// - **Day**: Selected day shown as filled accent circle; today as accent ring outline.
/// - **Week**: Selected week row highlighted as a continuous rounded band; today ring still visible.
///
/// Days with recorded session data show a small dot indicator below the day number.
struct ReportCalendarGrid: View {
    @Environment(ThemeManager.self) private var theme

    @Binding var selectedDate: Date
    let selectionMode: CalendarSelectionMode
    let weekStartDay: Int
    let earliestDate: Date?
    /// Dates (start-of-day) that have recorded session data.
    let datesWithData: Set<Date>
    let onDateSelected: (Date) -> Void
    /// Called when the displayed month changes (e.g., via navigation chevrons).
    var onMonthChanged: ((Date) -> Void)?

    @State private var displayedMonth: Date = Date()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let cellSize: CGFloat = 28

    var body: some View {
        VStack(spacing: Constants.spacingCard) {
            monthNavigation
            weekdayHeaders
            dayGrid
        }
        .onAppear {
            displayedMonth = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
        }
        .onChange(of: displayedMonth) { _, newMonth in
            onMonthChanged?(newMonth)
        }
    }

    // MARK: - Calendar

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = weekStartDay
        return cal
    }

    // MARK: - Month Navigation

    private var monthNavigation: some View {
        HStack {
            Button {
                navigateMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(!canNavigateMonthBack)
            .accessibilityLabel("Previous month")
            .help("Previous month")

            Spacer()

            Text(ChartFormatters.monthYear.string(from: displayedMonth))
                .font(.headline)

            Spacer()

            Button {
                navigateMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(!canNavigateMonthForward)
            .accessibilityLabel("Next month")
            .help("Next month")
        }
    }

    private var canNavigateMonthBack: Bool {
        guard let earliest = earliestDate else { return true }
        let earliestMonth = calendar.dateInterval(of: .month, for: earliest)?.start ?? earliest
        return displayedMonth > earliestMonth
    }

    private var canNavigateMonthForward: Bool {
        let currentMonth = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        return displayedMonth < currentMonth
    }

    private func navigateMonth(by offset: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth) {
            withAdaptiveAnimation(.easeInOut(duration: 0.2)) {
                displayedMonth = newMonth
            }
        }
    }

    // MARK: - Weekday Headers

    private var weekdayHeaders: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 20)
            }
        }
        .accessibilityHidden(true)
    }

    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let offset = weekStartDay - 1
        return Array(symbols[offset...]) + Array(symbols[..<offset])
    }

    // MARK: - Day Grid

    private var dayGrid: some View {
        let dates = gridDates
        let rows = stride(from: 0, to: dates.count, by: 7).map { Array(dates[$0..<min($0 + 7, dates.count)]) }

        return VStack(spacing: Constants.spacingTight) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                weekRow(dates: row, rowStartIndex: rowIndex * 7)
            }
        }
        .id(displayedMonth) // Force clean rebuild on month change to avoid AttributeGraph cycles
    }

    private func weekRow(dates: [Date], rowStartIndex: Int) -> some View {
        let isWeekSelected = selectionMode == .week && dates.contains(where: { isInSelectedWeek($0) })

        return HStack(spacing: 0) {
            ForEach(Array(dates.enumerated()), id: \.offset) { colIndex, date in
                dayCell(date: date, gridIndex: rowStartIndex + colIndex)
                    .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .top) {
            if isWeekSelected {
                Capsule()
                    .fill(theme.accent.opacity(0.12))
                    .frame(height: cellSize)
            }
        }
    }

    /// Compute 42 dates (6 rows × 7 columns) for the displayed month.
    private var gridDates: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else {
            return []
        }

        let firstOfMonth = monthInterval.start
        let weekdayOfFirst = calendar.component(.weekday, from: firstOfMonth)

        // Number of leading days from previous month
        var leadingDays = weekdayOfFirst - weekStartDay
        if leadingDays < 0 { leadingDays += 7 }

        // Start from the first visible day
        guard let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: firstOfMonth) else {
            return []
        }

        return (0..<42).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: gridStart)
        }
    }

    // MARK: - Day Cell

    @ViewBuilder
    private func dayCell(date: Date, gridIndex: Int) -> some View {
        let state = cellState(for: date)
        let isWeekSelected = selectionMode == .week && isInSelectedWeek(date)
        let hasData = datesWithData.contains(calendar.startOfDay(for: date))

        Button {
            selectDate(date)
        } label: {
            VStack(spacing: 4) {
                Text(dayNumber(date))
                    .font(.callout)
                    .monospacedDigit()
                    .frame(width: cellSize, height: cellSize)
                    .foregroundColor(foregroundColor(for: state, isWeekSelected: isWeekSelected))
                    .background(dayBackground(state: state))

                // Data indicator dot — sits below the circle, like iOS Calendar.
                // Always visible when data exists (even for selected/today).
                Circle()
                    .fill(dataDotColor(state: state, isWeekSelected: isWeekSelected))
                    .frame(width: 5, height: 5)
                    .opacity(hasData ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state == .disabled)
        .accessibilityLabel(fullDateLabel(date))
    }

    private func dayNumber(_ date: Date) -> String {
        String(calendar.component(.day, from: date))
    }

    private func fullDateLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    /// Dot color adapts to cell context so it remains visible against any background.
    /// Follows iOS Calendar pattern: accent dot below the day number, always visible when data exists.
    private func dataDotColor(state: CellState, isWeekSelected: Bool) -> Color {
        switch state {
        case .selected, .today:
            return theme.accent
        case .currentMonth:
            return isWeekSelected ? theme.accent : theme.accent.opacity(0.5)
        case .adjacentMonth:
            return theme.accent.opacity(0.25)
        case .disabled:
            return theme.accent.opacity(0.15)
        }
    }

    // MARK: - Cell State

    private enum CellState {
        case selected
        case today
        case currentMonth
        case adjacentMonth
        case disabled
    }

    private func cellState(for date: Date) -> CellState {
        let startOfDay = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())

        // Disabled: before earliest or after today
        if let earliest = earliestDate, startOfDay < calendar.startOfDay(for: earliest) {
            return .disabled
        }
        if startOfDay > today {
            return .disabled
        }

        // Selected (day mode only — week mode uses the band)
        if selectionMode == .day && calendar.isDate(date, inSameDayAs: selectedDate) {
            return .selected
        }

        // Today
        if startOfDay == today {
            return .today
        }

        // Current vs adjacent month
        if let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
           startOfDay >= monthInterval.start && startOfDay < monthInterval.end {
            return .currentMonth
        }

        return .adjacentMonth
    }

    // MARK: - Foreground Colors

    private func foregroundColor(for state: CellState, isWeekSelected: Bool) -> Color {
        switch state {
        case .selected:
            return theme.constantWhite
        case .today:
            return theme.accent
        case .currentMonth:
            return isWeekSelected ? theme.accent : .primary
        case .adjacentMonth:
            return .secondary.opacity(0.5)
        case .disabled:
            return .secondary.opacity(0.25)
        }
    }

    // MARK: - Day Background (selected circle / today ring)

    @ViewBuilder
    private func dayBackground(state: CellState) -> some View {
        switch state {
        case .selected:
            Circle()
                .fill(theme.accent.opacity(0.12))
                .frame(width: cellSize, height: cellSize)
        case .today:
            Circle()
                .strokeBorder(theme.accent, lineWidth: 1.5)
                .frame(width: cellSize, height: cellSize)
        default:
            Color.clear
        }
    }

    // MARK: - Week Selection

    private func isInSelectedWeek(_ date: Date) -> Bool {
        guard let selectedWeek = calendar.dateInterval(of: .weekOfYear, for: selectedDate),
              let dateWeek = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return false
        }
        return selectedWeek == dateWeek
    }

    // MARK: - Selection

    private func selectDate(_ date: Date) {
        // If tapping an adjacent-month day, navigate to that month
        if let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
           (date < monthInterval.start || date >= monthInterval.end) {
            if let newMonth = calendar.dateInterval(of: .month, for: date)?.start {
                withAdaptiveAnimation(.easeInOut(duration: 0.2)) {
                    displayedMonth = newMonth
                }
            }
        }

        selectedDate = date
        onDateSelected(date)
    }
}
