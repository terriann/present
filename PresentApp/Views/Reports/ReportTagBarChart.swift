import SwiftUI
import Charts
import PresentCore

struct ReportTagBarChart: View {
    let tagActivitySummaries: [TagActivitySummary]
    let activities: [ActivitySummary]
    let chartColorDomain: [String]
    let chartColorRange: [Color]
    let activityColorMap: [String: Color]
    /// Tag names that include active session data. Matching bars pulse.
    var activeTagNames: Set<String> = []

    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hoveredTagName: String?
    @State private var tagHoverLocation: CGPoint = .zero
    @State private var pulseState = ActivePulseState()

    private var hasActiveEntries: Bool {
        !activeTagNames.isEmpty
    }

    var body: some View {
        // Guard: chartForegroundStyleScale crashes on empty domain (FB…).
        if !chartColorDomain.isEmpty {
            let sorted = tagActivitySummaries.sorted { $0.totalSeconds > $1.totalSeconds }
            let barHeight: CGFloat = max(120, CGFloat(sorted.count) * 36 + 40)

            // Flatten into entries for the stacked bar
            let entries: [TagBarEntry] = sorted.flatMap { tag in
                let isActive = activeTagNames.contains(tag.tagName)
                let duration = TimeFormatting.formatDuration(seconds: tag.totalSeconds, active: isActive)
                let yLabel = "\(tag.tagName) \u{00B7} \(duration) (\(tag.activityCount))"
                return tag.activities.map { summary in
                    TagBarEntry(
                        tagName: tag.tagName,
                        tagLabel: yLabel,
                        activityTitle: summary.activity.title,
                        hours: Double(summary.totalSeconds) / 3600.0,
                        totalSeconds: tag.totalSeconds,
                        isActive: isActive
                    )
                }
            }

            ChartCard(title: "Tag Distribution") {
                tagBarChart(entries: entries, sorted: sorted, barHeight: barHeight)
            }
            .onChange(of: hasActiveEntries) {
                if hasActiveEntries {
                    pulseState.start(reduceMotion: reduceMotion)
                } else {
                    pulseState.stop()
                }
            }
            .onAppear {
                if hasActiveEntries {
                    pulseState.start(reduceMotion: reduceMotion)
                }
            }
            .onDisappear {
                pulseState.stop()
            }
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
            .opacity(tagBarOpacity(entry: entry))
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tag distribution chart")
        .accessibilityValue(tagChartAccessibilityValue(sorted: sorted))
        .frame(height: barHeight)
        .padding(Constants.spacingCard)
    }

    // MARK: - Accessibility

    private func tagChartAccessibilityValue(sorted: [TagActivitySummary]) -> String {
        sorted.map { "\($0.tagName): \(TimeFormatting.formatDuration(seconds: $0.totalSeconds))" }
            .joined(separator: ", ")
    }

    // MARK: - Opacity

    private func tagBarOpacity(entry: TagBarEntry) -> Double {
        // Hover dimming takes priority
        if hoveredTagName != nil {
            return hoveredTagName == entry.tagName ? 1.0 : 0.4
        }
        // Pulse active tag bars when no hover is active
        if entry.isActive { return pulseState.opacity }
        return 1.0
    }

    // MARK: - Tooltip

    private func tagTooltip(forTag tagName: String?, summaries: [TagActivitySummary]) -> some View {
        let matching = summaries.first { $0.tagName == tagName }
        let isActive = tagName.map { activeTagNames.contains($0) } ?? false

        return ChartTooltip {
            if let tag = matching {
                Text(tag.tagName)
                    .font(.dataLabel)

                ForEach(tag.activities, id: \.activity.id) { summary in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(activityColorMap[summary.activity.title] ?? .secondary)
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
                        Text(TimeFormatting.formatDuration(seconds: tag.totalSeconds, active: isActive))
                            .font(.dataBoldValue)
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Types

struct TagBarEntry: Identifiable {
    /// Deterministic ID for stable chart identity during per-second active session updates.
    var id: String { "\(tagName)-\(activityTitle)" }
    let tagName: String
    let tagLabel: String
    let activityTitle: String
    let hours: Double
    let totalSeconds: Int
    var isActive: Bool = false
}
