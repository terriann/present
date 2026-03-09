import SwiftUI
import Charts
import PresentCore

struct ReportExternalIdChart: View {
    let groups: [ExternalIdSummary]
    /// External ID of the active session, if any. Matching sector pulses.
    var activeExternalId: String?

    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var externalIdAngleSelection: Int?
    @State private var hoveredExternalSegment: String?
    @State private var pulseState = ActivePulseState()

    private var hasActiveEntry: Bool {
        activeExternalId != nil && groups.contains { $0.externalId == activeExternalId }
    }

    var body: some View {
        guard !groups.isEmpty else { return AnyView(EmptyView()) }
        let combinedTotal = groups.reduce(0) { $0 + $1.totalSeconds }
        let palette = ThemeManager.chartColors(for: theme.activePalette)

        return AnyView(
            ChartCard(title: "External ID Breakdown", headerTrailing: {
                ExternalIdInfoButton()
            }) {
                externalIdDonutChart(combinedTotal: combinedTotal, palette: palette)
                externalIdLegend(palette: palette)
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
        )
    }

    // MARK: - Donut Chart

    private func externalIdDonutChart(
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
            .opacity(sectorOpacity(for: group.externalId))
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
                        let isActive = segmentId == activeExternalId
                        DonutCenterTooltip {
                            Text(group.externalId)
                                .font(.dataLabel)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            Text(TimeFormatting.formatDuration(seconds: group.totalSeconds, active: isActive))
                                .font(.dataValue)
                            let pct = combinedTotal > 0 ? Double(group.totalSeconds) / Double(combinedTotal) * 100 : 0
                            Text(String(format: "%.1f%%", pct))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            ForEach(group.activityNames, id: \.self) { name in
                                Text(name)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("External ID breakdown chart")
        .accessibilityValue(chartAccessibilityValue(combinedTotal: combinedTotal))
        .frame(height: 250)
        .padding(Constants.spacingCard)
    }

    // MARK: - Accessibility

    private func chartAccessibilityValue(combinedTotal: Int) -> String {
        groups.map { group in
            let pct = combinedTotal > 0 ? Double(group.totalSeconds) / Double(combinedTotal) * 100 : 0
            return "\(group.externalId): \(TimeFormatting.formatDuration(seconds: group.totalSeconds)) (\(String(format: "%.1f%%", pct)))"
        }.joined(separator: ", ")
    }

    // MARK: - Legend

    private func externalIdLegend(palette: [Color]) -> some View {
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

    private func sectorOpacity(for externalId: String) -> Double {
        // Hover dimming takes priority
        if hoveredExternalSegment != nil {
            return hoveredExternalSegment == externalId ? 1.0 : 0.4
        }
        // Pulse the active sector when no hover is active
        if externalId == activeExternalId { return pulseState.opacity }
        return 1.0
    }

    private func findExternalSegment(for value: Int?) -> String? {
        guard let value else { return nil }
        var cumulative = 0
        for group in groups {
            cumulative += group.totalSeconds
            if value <= cumulative {
                return group.externalId
            }
        }
        return nil
    }
}

// MARK: - Info Button

struct ExternalIdInfoButton: View {
    @State private var showInfo = false

    var body: some View {
        Button {
            showInfo.toggle()
        } label: {
            Image(systemName: "info.circle.fill")
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("External ID grouping info")
        .popover(isPresented: $showInfo) {
            ExternalIdInfoContent()
        }
    }
}

// MARK: - Info Popover Content

private struct ExternalIdInfoContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Constants.spacingCompact) {
            Text("How time is grouped")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text("Time is grouped by external ID. When a session has its own ticket ID (from a linked URL), that takes precedence over the activity's external ID. Each session's time counts toward one external ID only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 280)
    }
}
