import SwiftUI
import Charts
import PresentCore

struct ReportActivityPieChart: View {
    let activities: [ActivitySummary]
    let totalSeconds: Int
    let chartColorDomain: [String]
    let chartColorRange: [Color]
    let activityColorMap: [String: Color]
    /// Title of the active session's activity, if any. Matching sector pulses.
    var activeActivityTitle: String?

    @Environment(ThemeManager.self) private var theme

    @State private var activityAngleSelection: Int?
    @State private var hoveredActivityName: String?
    @State private var legendHoveredActivity: String?

    var body: some View {
        // Guard: chartForegroundStyleScale crashes on empty domain (FB…).
        if !chartColorDomain.isEmpty {
            ChartCard(title: "Activity Distribution") {
                activityDonutChart
                activityDonutLegend
            }
        }
    }

    // MARK: - Donut Chart

    private var activityDonutChart: some View {
        Chart(activities, id: \.activity.id) { summary in
            SectorMark(
                angle: .value("Time", summary.totalSeconds),
                innerRadius: .ratio(0.5),
                angularInset: 1
            )
            .foregroundStyle(by: .value("Activity", summary.activity.title))
            .opacity(sectorOpacity(for: summary.activity.title))
        }
        .transaction { $0.animation = nil }
        .chartForegroundStyleScale(domain: chartColorDomain, range: chartColorRange)
        .chartAngleSelection(value: $activityAngleSelection)
        .onChange(of: activityAngleSelection) {
            if legendHoveredActivity == nil {
                hoveredActivityName = findActivity(for: activityAngleSelection)
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    if let name = hoveredActivityName,
                       let summary = activities.first(where: { $0.activity.title == name }) {
                        let isActive = name == activeActivityTitle
                        DonutCenterTooltip {
                            Text(summary.activity.title)
                                .font(.dataLabel)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            Text(TimeFormatting.formatDuration(seconds: summary.totalSeconds, active: isActive))
                                .font(.dataValue)
                            let pct = totalSeconds > 0 ? Double(summary.totalSeconds) / Double(totalSeconds) * 100 : 0
                            Text(String(format: "%.1f%%", pct))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(summary.sessionCount) sessions")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .position(
                            x: frame.midX,
                            y: frame.midY
                        )
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Activity distribution chart")
        .accessibilityValue(chartAccessibilityValue)
        .frame(height: 250)
        .padding(Constants.spacingCard)
    }

    // MARK: - Accessibility

    private var chartAccessibilityValue: String {
        activities.map { summary in
            let pct = totalSeconds > 0 ? Double(summary.totalSeconds) / Double(totalSeconds) * 100 : 0
            return "\(summary.activity.title): \(TimeFormatting.formatDuration(seconds: summary.totalSeconds)) (\(String(format: "%.1f%%", pct)))"
        }.joined(separator: ", ")
    }

    // MARK: - Legend

    private var activityDonutLegend: some View {
        HoverableChartLegend(
            items: chartColorDomain.map { title in
                (label: title, color: activityColorMap[title] ?? .secondary)
            },
            hoveredLabel: $hoveredActivityName,
            onHoverStart: { label in
                legendHoveredActivity = label
            },
            onHoverEnd: {
                legendHoveredActivity = nil
                hoveredActivityName = findActivity(for: activityAngleSelection)
            }
        )
        .padding(.horizontal, Constants.spacingCard)
        .padding(.bottom, Constants.spacingCard)
    }

    // MARK: - Helpers

    private func sectorOpacity(for title: String) -> Double {
        // Hover dimming takes priority
        if hoveredActivityName != nil {
            return hoveredActivityName == title ? 1.0 : 0.4
        }
        return 1.0
    }

    private func findActivity(for value: Int?) -> String? {
        guard let value else { return nil }
        var cumulative = 0
        for summary in activities {
            cumulative += summary.totalSeconds
            if value <= cumulative {
                return summary.activity.title
            }
        }
        return nil
    }
}
