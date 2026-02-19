import SwiftUI

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
