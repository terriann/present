import SwiftUI
import Charts
import PresentCore

struct ReportExternalIdChart: View {
    let groups: [ExternalIdSummary]
    /// External ID of the active session, if any. Matching sector pulses.
    var activeExternalId: String?

    @Environment(ThemeManager.self) private var theme
    @Environment(\.openURL) private var openURL

    @State private var externalIdAngleSelection: Int?
    @State private var hoveredExternalSegment: String?

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
                ExternalIdLegendRow(
                    group: group,
                    color: palette[index % palette.count],
                    combinedTotal: combinedTotal,
                    isHighlighted: hoveredExternalSegment == group.externalId,
                    onHighlight: { hoveredExternalSegment = group.externalId },
                    onUnhighlight: {
                        hoveredExternalSegment = findExternalSegment(for: externalIdAngleSelection)
                    }
                )
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

// MARK: - Legend Row

/// A single legend row that supports hover, keyboard focus, and VoiceOver.
private struct ExternalIdLegendRow: View {
    let group: ExternalIdSummary
    let color: Color
    let combinedTotal: Int
    let isHighlighted: Bool
    let onHighlight: () -> Void
    let onUnhighlight: () -> Void

    @Environment(\.openURL) private var openURL
    @AccessibilityFocusState private var isAccessibilityFocused: Bool
    @FocusState private var isKeyboardFocused: Bool

    private var pct: Double {
        combinedTotal > 0 ? Double(group.totalSeconds) / Double(combinedTotal) * 100 : 0
    }

    var body: some View {
        HStack(alignment: .center, spacing: Constants.spacingTight) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
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
            RoundedRectangle(cornerRadius: Constants.cornerRadiusSmall)
                .fill(isHighlighted ? Color.primary.opacity(0.08) : Color.clear)
        )
        .focusable()
        .focused($isKeyboardFocused)
        .accessibilityFocused($isAccessibilityFocused)
        .accessibilityLabel("\(group.externalId), \(TimeFormatting.formatDuration(seconds: group.totalSeconds)), \(String(format: "%.0f%%", pct))")
        .accessibilityValue(group.activityNames.sorted().joined(separator: ", "))
        .onHover { hovering in
            if hovering { onHighlight() } else { onUnhighlight() }
        }
        .onChange(of: isKeyboardFocused) {
            if isKeyboardFocused { onHighlight() } else { onUnhighlight() }
        }
        .onChange(of: isAccessibilityFocused) {
            if isAccessibilityFocused { onHighlight() } else { onUnhighlight() }
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
