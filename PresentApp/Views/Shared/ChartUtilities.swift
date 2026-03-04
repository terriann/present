import SwiftUI
import Charts

// MARK: - Cached Formatters

/// Reusable `DateFormatter` instances for chart and report label generation.
///
/// `DateFormatter` is one of the most expensive Foundation objects to construct.
/// These static lets are allocated once at first access and shared across all views.
enum ChartFormatters {
    /// Short weekday name — "Mon", "Tue", etc. (format: `EEE`)
    static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    /// Hour with AM/PM — "9AM", "2PM", etc. (format: `ha`)
    static let hour: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "ha"
        return f
    }()

    /// Day number — "1", "15", "31", etc. (format: `d`)
    static let dayNumber: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    /// Full date — "Monday, March 2, 2026" (dateStyle: `.full`)
    static let fullDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        return f
    }()

    /// Month and year — "March 2026" (format: `MMMM yyyy`)
    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    /// Full day name with date — "Monday, March 2" (format: `EEEE, MMMM d`)
    static let fullDayName: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()
}

/// Returns the set of x-axis labels that fall on weekends (Saturday or Sunday).
///
/// - Weekly mode: returns "EEE" labels (e.g. "Sat", "Sun") for weekend days in the week.
/// - Monthly mode: returns day-number strings (e.g. "7", "14") for all weekend days in the month.
func weekendLabels(
    period: WeekendPeriod,
    weekStartDay: Int,
    selectedDate: Date
) -> Set<String> {
    var calendar = Calendar.current
    calendar.firstWeekday = weekStartDay
    var result = Set<String>()

    switch period {
    case .weekly:
        guard let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start else {
            return result
        }
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let weekday = calendar.component(.weekday, from: date)
            if weekday == 1 || weekday == 7 { // Sunday or Saturday
                result.insert(ChartFormatters.weekday.string(from: date))
            }
        }

    case .monthly:
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate) else {
            return result
        }
        var date = monthInterval.start
        while date < monthInterval.end {
            let weekday = calendar.component(.weekday, from: date)
            if weekday == 1 || weekday == 7 {
                result.insert(ChartFormatters.dayNumber.string(from: date))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
    }

    return result
}

enum WeekendPeriod {
    case weekly
    case monthly
}

/// Builds a mapping from short weekday labels ("EEE") to full date strings ("EEEE, MMMM d")
/// for each day in the week containing `referenceDate`.
func weeklyTooltipLabels(weekStartDay: Int, referenceDate: Date) -> [String: String] {
    var calendar = Calendar.current
    calendar.firstWeekday = weekStartDay
    guard let start = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start else { return [:] }

    var mapping: [String: String] = [:]
    for offset in 0..<7 {
        guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
        mapping[ChartFormatters.weekday.string(from: date)] = ChartFormatters.fullDayName.string(from: date)
    }
    return mapping
}

/// Calculates tooltip center position near the cursor, flipping sides and clamping to stay
/// at least 6pt from each edge of the container.
func tooltipPosition(cursor: CGPoint, containerSize: CGSize) -> CGPoint {
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

// MARK: - View Extensions

extension View {
    /// Applies hover-based opacity: full when highlighted or nothing hovered, faded otherwise.
    func chartHoverOpacity(isHighlighted: Bool) -> some View {
        self.opacity(isHighlighted ? 1.0 : 0.4)
    }
}
