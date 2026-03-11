import SwiftUI
import PresentCore

struct HoverableChartLegend: View {
    let items: [(label: String, color: Color)]
    @Binding var hoveredLabel: String?
    var onHoverStart: ((String) -> Void)?
    var onHoverEnd: (() -> Void)?

    /// Deduplicated items — keeps the first occurrence of each label.
    private var uniqueItems: [(label: String, color: Color)] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.label).inserted }
    }

    var body: some View {
        FlowLayout(spacing: Constants.spacingCompact) {
            ForEach(uniqueItems, id: \.label) { item in
                HStack(spacing: Constants.spacingTight) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 8, height: 8)
                    Text(item.label)
                        .font(.caption)
                        .lineLimit(1)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hoveredLabel == item.label ? Color.primary.opacity(0.08) : Color.clear)
                )
                .onHover { hovering in
                    if hovering {
                        hoveredLabel = item.label
                        onHoverStart?(item.label)
                    } else {
                        hoveredLabel = nil
                        onHoverEnd?()
                    }
                }
            }
        }
    }
}
