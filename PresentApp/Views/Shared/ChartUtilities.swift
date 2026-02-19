import SwiftUI
import Charts

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
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        guard let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start else {
            return result
        }
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let weekday = calendar.component(.weekday, from: date)
            if weekday == 1 || weekday == 7 { // Sunday or Saturday
                result.insert(formatter.string(from: date))
            }
        }

    case .monthly:
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate) else {
            return result
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        var date = monthInterval.start
        while date < monthInterval.end {
            let weekday = calendar.component(.weekday, from: date)
            if weekday == 1 || weekday == 7 {
                result.insert(formatter.string(from: date))
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

    let shortFormatter = DateFormatter()
    shortFormatter.dateFormat = "EEE"
    let fullFormatter = DateFormatter()
    fullFormatter.dateFormat = "EEEE, MMMM d"

    var mapping: [String: String] = [:]
    for offset in 0..<7 {
        guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
        mapping[shortFormatter.string(from: date)] = fullFormatter.string(from: date)
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
