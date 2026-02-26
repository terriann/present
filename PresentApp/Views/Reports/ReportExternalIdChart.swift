import SwiftUI
import Charts
import PresentCore

struct ReportExternalIdChart: View {
    let activities: [ActivitySummary]

    @Environment(ThemeManager.self) private var theme

    @State private var externalIdAngleSelection: Int?
    @State private var hoveredExternalSegment: String?

    private var externalIdGroups: [(externalId: String, activities: [ActivitySummary], totalSeconds: Int)] {
        var grouped: [String: [ActivitySummary]] = [:]
        for summary in activities {
            if let externalId = summary.activity.externalId {
                grouped[externalId, default: []].append(summary)
            }
        }
        return grouped.map { (externalId: $0.key, activities: $0.value, totalSeconds: $0.value.reduce(0) { $0 + $1.totalSeconds }) }
            .sorted { $0.totalSeconds > $1.totalSeconds }
    }

    var body: some View {
        let groups = externalIdGroups
        guard !groups.isEmpty else { return AnyView(EmptyView()) }
        let combinedTotal = groups.reduce(0) { $0 + $1.totalSeconds }
        let palette = ThemeManager.chartColors(for: theme.activePalette)

        return AnyView(
            ChartCard(title: "External ID Breakdown") {
                externalIdDonutChart(groups: groups, combinedTotal: combinedTotal, palette: palette)
                externalIdLegend(groups: groups, palette: palette)
            }
        )
    }

    // MARK: - Donut Chart

    private func externalIdDonutChart(
        groups: [(externalId: String, activities: [ActivitySummary], totalSeconds: Int)],
        combinedTotal: Int,
        palette: [Color]
    ) -> some View {
        Chart(groups, id: \.externalId) { group in
            SectorMark(
                angle: .value("Time", group.totalSeconds),
                innerRadius: .ratio(0.5),
                angularInset: 1
            )
            .foregroundStyle(by: .value("External ID", group.externalId))
            .opacity(hoveredExternalSegment == nil || hoveredExternalSegment == group.externalId ? 1.0 : 0.4)
        }
        .chartForegroundStyleScale(
            domain: groups.map(\.externalId),
            range: groups.indices.map { palette[$0 % palette.count] }
        )
        .chartAngleSelection(value: $externalIdAngleSelection)
        .onChange(of: externalIdAngleSelection) {
            hoveredExternalSegment = findExternalSegment(for: externalIdAngleSelection)
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    if let segmentId = hoveredExternalSegment,
                       let group = groups.first(where: { $0.externalId == segmentId }) {
                        DonutCenterTooltip {
                            Text(group.externalId)
                                .font(.dataLabel)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            Text(TimeFormatting.formatDuration(seconds: group.totalSeconds))
                                .font(.dataValue)
                            let pct = combinedTotal > 0 ? Double(group.totalSeconds) / Double(combinedTotal) * 100 : 0
                            Text(String(format: "%.1f%%", pct))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            ForEach(group.activities, id: \.activity.id) { summary in
                                Text(summary.activity.title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
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

    private func externalIdLegend(
        groups: [(externalId: String, activities: [ActivitySummary], totalSeconds: Int)],
        palette: [Color]
    ) -> some View {
        HoverableChartLegend(
            items: groups.enumerated().map { index, group in
                (label: group.externalId, color: palette[index % palette.count])
            },
            hoveredLabel: $hoveredExternalSegment,
            onHoverEnd: {
                hoveredExternalSegment = findExternalSegment(for: externalIdAngleSelection)
            }
        )
        .padding(.horizontal, Constants.spacingCard)
        .padding(.bottom, Constants.spacingCard)
    }

    // MARK: - Helpers

    private func findExternalSegment(for value: Int?) -> String? {
        guard let value else { return nil }
        var cumulative = 0
        for group in externalIdGroups {
            cumulative += group.totalSeconds
            if value <= cumulative {
                return group.externalId
            }
        }
        return nil
    }
}
