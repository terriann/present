import SwiftUI
import Charts
import PresentCore

struct ReportActivityPieChart: View {
    let activities: [ActivitySummary]
    let totalSeconds: Int
    let chartColorDomain: [String]
    let chartColorRange: [Color]
    /// Title of the active session's activity, if any. Matching sector pulses.
    var activeActivityTitle: String?

    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var activityAngleSelection: Int?
    @State private var hoveredActivityName: String?
    @State private var legendHoveredActivity: String?
    @State private var pulseState = ActivePulseState()

    private var hasActiveEntry: Bool {
        activeActivityTitle != nil
    }

    var body: some View {
        let palette = ThemeManager.chartColors(for: theme.activePalette)

        ChartCard(title: "Activity Distribution") {
            activityDonutChart
            activityDonutLegend(palette: palette)
        }
        .onChange(of: hasActiveEntry) {
            if hasActiveEntry {
                pulseState.start(reduceMotion: reduceMotion)
            } else {
                pulseState.stop()
            }
        }
        .onAppear {
            if hasActiveEntry {
                pulseState.start(reduceMotion: reduceMotion)
            }
        }
        .onDisappear {
            pulseState.stop()
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
        .frame(height: 250)
        .padding(Constants.spacingCard)
    }

    // MARK: - Legend

    private func activityDonutLegend(palette: [Color]) -> some View {
        HoverableChartLegend(
            items: activities.enumerated().map { index, summary in
                (label: summary.activity.title, color: palette[index % palette.count])
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
        // Pulse the active sector when no hover is active
        if title == activeActivityTitle { return pulseState.opacity }
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
