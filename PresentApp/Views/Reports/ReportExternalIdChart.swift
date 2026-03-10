import SwiftUI
import Charts
import PresentCore

struct ReportExternalIdChart: View {
    let groups: [ExternalIdSummary]
    /// External ID of the active session, if any. Matching sector pulses.
    var activeExternalId: String?

    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

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
                HStack(alignment: .top, spacing: Constants.spacingCard) {
                    externalIdDonutChart(combinedTotal: combinedTotal, palette: palette)
                    externalIdLegend(palette: palette, combinedTotal: combinedTotal)
                }
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
                            Text(String(format: "%.0f%%", pct))
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

    private func externalIdLegend(palette: [Color], combinedTotal: Int) -> some View {
        VStack(alignment: .leading, spacing: Constants.spacingCard) {
            ForEach(Array(groups.enumerated()), id: \.element.externalId) { index, group in
                let color = palette[index % palette.count]
                let isHovered = hoveredExternalSegment == group.externalId
                HStack(alignment: .center, spacing: Constants.spacingTight) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: Constants.spacingTight) {
                        Text(group.externalId)
                            .font(.dataLabel)
                            .lineLimit(1)
                        Text(group.activityNames.sorted().joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    HStack(alignment: .center, spacing: Constants.spacingCompact) {
                        let pct = combinedTotal > 0 ? Double(group.totalSeconds) / Double(combinedTotal) * 100 : 0
                        Text(String(format: "%.0f%%", pct))
                            .font(.dataValue)
                            .foregroundStyle(.secondary)
                        if let urlString = group.sourceURL, let url = URL(string: urlString) {
                            Button {
                                openURL(url)
                            } label: {
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open \(group.externalId)")
                            .help(urlString)
                        }
                    }
                }
                .padding(.vertical, Constants.spacingTight)
                .padding(.horizontal, Constants.spacingCompact)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                )
                .onHover { hovering in
                    if hovering {
                        hoveredExternalSegment = group.externalId
                    } else {
                        hoveredExternalSegment = nil
                        hoveredExternalSegment = findExternalSegment(for: externalIdAngleSelection)
                    }
                }
            }
        }
        .padding(.horizontal, Constants.spacingCard)
        .padding(.bottom, Constants.spacingCard)
        .frame(maxWidth: .infinity, alignment: .leading)
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
