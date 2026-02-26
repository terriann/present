import SwiftUI
import Charts
import PresentCore

struct ReportTagBarChart: View {
    let tagActivitySummaries: [TagActivitySummary]
    let activities: [ActivitySummary]
    let chartColorDomain: [String]
    let chartColorRange: [Color]

    @Environment(ThemeManager.self) private var theme

    @State private var hoveredTagName: String?
    @State private var tagHoverLocation: CGPoint = .zero

    var body: some View {
        let sorted = tagActivitySummaries.sorted { $0.totalSeconds > $1.totalSeconds }
        let barHeight: CGFloat = max(120, CGFloat(sorted.count) * 36 + 40)

        // Flatten into entries for the stacked bar
        let entries: [TagBarEntry] = sorted.flatMap { tag in
            let duration = TimeFormatting.formatDuration(seconds: tag.totalSeconds)
            let yLabel = "\(tag.tagName) \u{00B7} \(duration) (\(tag.activityCount))"
            return tag.activities.map { summary in
                TagBarEntry(
                    tagName: tag.tagName,
                    tagLabel: yLabel,
                    activityTitle: summary.activity.title,
                    hours: Double(summary.totalSeconds) / 3600.0,
                    totalSeconds: tag.totalSeconds
                )
            }
        }

        ChartCard(title: "Tag Distribution") {
            tagBarChart(entries: entries, sorted: sorted, barHeight: barHeight)
        }
    }

    // MARK: - Chart

    private func tagBarChart(entries: [TagBarEntry], sorted: [TagActivitySummary], barHeight: CGFloat) -> some View {
        Chart(entries, id: \.id) { entry in
            BarMark(
                x: .value("Hours", entry.hours),
                y: .value("Tag", entry.tagLabel)
            )
            .foregroundStyle(by: .value("Activity", entry.activityTitle))
            .opacity(hoveredTagName == nil || hoveredTagName == entry.tagName ? 1.0 : 0.4)
        }
        .chartForegroundStyleScale(domain: chartColorDomain, range: chartColorRange)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))h")
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]

                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let relativeY = location.y - frame.origin.y
                                if let label: String = proxy.value(atY: relativeY),
                                   let entry = entries.first(where: { $0.tagLabel == label }) {
                                    hoveredTagName = entry.tagName
                                    tagHoverLocation = location
                                } else {
                                    hoveredTagName = nil
                                }
                            case .ended:
                                hoveredTagName = nil
                            }
                        }

                    if let tagName = hoveredTagName {
                        let pos = tooltipPosition(cursor: tagHoverLocation, containerSize: geometry.size)
                        tagTooltip(forTag: tagName, summaries: sorted)
                            .fixedSize()
                            .frame(maxWidth: 200, alignment: .leading)
                            .position(x: pos.x, y: pos.y)
                    }
                }
            }
        }
        .frame(height: barHeight)
        .padding(Constants.spacingCard)
    }

    // MARK: - Tooltip

    private func tagTooltip(forTag tagName: String?, summaries: [TagActivitySummary]) -> some View {
        let matching = summaries.first { $0.tagName == tagName }
        let palette = ThemeManager.chartColors(for: theme.activePalette)

        return ChartTooltip {
            if let tag = matching {
                Text(tag.tagName)
                    .font(.dataLabel)

                ForEach(tag.activities, id: \.activity.id) { summary in
                    HStack(spacing: 6) {
                        let color = activities.firstIndex(where: { $0.activity.title == summary.activity.title })
                            .map { palette[$0 % palette.count] } ?? .secondary
                        Circle()
                            .fill(color)
                            .frame(width: 8, height: 8)
                        Text(summary.activity.title)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(TimeFormatting.formatDuration(seconds: summary.totalSeconds))
                            .font(.dataValue)
                    }
                }

                if tag.activities.count > 1 {
                    Divider()
                    HStack {
                        Text("Total")
                            .font(.dataLabel)
                        Spacer()
                        Text(TimeFormatting.formatDuration(seconds: tag.totalSeconds))
                            .font(.dataBoldValue)
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Types

struct TagBarEntry: Identifiable {
    let id = UUID()
    let tagName: String
    let tagLabel: String
    let activityTitle: String
    let hours: Double
    let totalSeconds: Int
}
