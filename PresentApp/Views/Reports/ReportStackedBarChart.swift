import SwiftUI
import Charts
import PresentCore

struct ReportStackedBarChart: View {
    let entries: [BarEntry]
    let domain: [String]
    let tooltipLabels: [String: String]
    let selectedPeriod: ReportPeriod
    let activities: [ActivitySummary]
    let chartColorDomain: [String]
    let chartColorRange: [Color]
    let activityColorMap: [String: Color]
    let weekendDayLabels: Set<String>

    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hoveredBarLabel: String?
    @State private var hoveredBarActivity: String?
    @State private var barHoverLocation: CGPoint = .zero
    @State private var pulseState = ActivePulseState()

    private var yAxisLabel: String {
        selectedPeriod == .daily ? "Minutes" : "Hours"
    }

    private var yAxisDomain: ClosedRange<Double> {
        var labelTotals: [String: Double] = [:]
        for entry in entries {
            labelTotals[entry.label, default: 0] += entry.value
        }
        let peak = labelTotals.values.max() ?? 0
        let rounded = max(5, ceil(peak / 5) * 5)
        if selectedPeriod == .daily {
            return 0...rounded
        } else {
            // +1 so the rounded multiple appears as a visible axis mark
            return 0...min(rounded + 1, 25)
        }
    }

    private var hasActiveEntries: Bool {
        entries.contains { $0.isActive }
    }

    var body: some View {
        // Guard: chartForegroundStyleScale crashes on empty domain (FB…).
        // During reload transitions the parent may clear state, leaving domain empty
        // while the attribute graph still evaluates this view.
        if !chartColorDomain.isEmpty {
            ChartCard(title: "Time by \(selectedPeriod.timeLabel)") {
                stackedBarChart
                barChartLegend
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

    // MARK: - Bar Chart

    private var stackedBarChart: some View {
        let weekends = weekendDayLabels

        return Chart {
            ForEach(entries, id: \.id) { entry in
                BarMark(
                    x: .value(selectedPeriod.timeLabel, entry.label),
                    y: .value(yAxisLabel, entry.value)
                )
                .foregroundStyle(by: .value("Activity", entry.activity))
                .opacity(barEntryOpacity(entry: entry))
            }
        }
        .chartForegroundStyleScale(domain: chartColorDomain, range: chartColorRange)
        .chartXScale(domain: domain)
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisTick()
                if let label = value.as(String.self), shouldShowXAxisLabel(label) {
                    AxisValueLabel()
                }
            }
        }
        .chartYScale(domain: yAxisDomain)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(selectedPeriod == .daily ? "\(Int(v))m" : "\(Int(v))h")
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
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let relativeX = location.x - frame.origin.x
                                if let label: String = proxy.value(atX: relativeX),
                                   entries.contains(where: { $0.label == label }) {
                                    hoveredBarLabel = label
                                    barHoverLocation = location
                                } else {
                                    hoveredBarLabel = nil
                                }
                            case .ended:
                                hoveredBarLabel = nil
                            }
                        }

                    if let label = hoveredBarLabel {
                        let pos = tooltipPosition(cursor: barHoverLocation, containerSize: geometry.size)
                        barTooltip(for: label)
                            .fixedSize()
                            .frame(maxWidth: 180, alignment: .leading)
                            .position(x: pos.x, y: pos.y)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartBackground { proxy in
            GeometryReader { geo in
                if let plotFrame = proxy.plotFrame {
                    let frame = geo[plotFrame]
                    ForEach(Array(weekends), id: \.self) { label in
                        if let xPos = proxy.position(forX: label) {
                            Rectangle()
                                .fill(theme.constantWhite.opacity(0.04))
                                .frame(width: frame.width / CGFloat(domain.count), height: geo.size.height)
                                .position(x: frame.origin.x + xPos, y: geo.size.height / 2)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Time by \(selectedPeriod.timeLabel) chart")
        .accessibilityValue(chartAccessibilityValue)
        .frame(height: 250)
        .padding(Constants.spacingCard)
    }

    // MARK: - Accessibility

    private var chartAccessibilityValue: String {
        let multiplier: Double = selectedPeriod == .daily ? 60 : 3600
        var grouped: [String: Double] = [:]
        for entry in entries {
            grouped[entry.activity, default: 0] += entry.value
        }
        let sorted = grouped.sorted { $0.value > $1.value }
        return sorted.map { "\($0.key): \(TimeFormatting.formatDuration(seconds: Int(($0.value * multiplier).rounded())))" }
            .joined(separator: ", ")
    }

    // MARK: - Legend

    private var barChartLegend: some View {
        let items = chartColorDomain.map { title in
            (label: title, color: activityColorMap[title] ?? .secondary)
        }
        return HoverableChartLegend(
            items: items,
            hoveredLabel: $hoveredBarActivity
        )
        .padding(.horizontal, Constants.spacingCard)
        .padding(.bottom, Constants.spacingCard)
    }

    // MARK: - Helpers

    private func barEntryOpacity(entry: BarEntry) -> Double {
        // Legend hover takes priority — isolate a single activity across all hours
        if let activity = hoveredBarActivity {
            return entry.activity == activity ? 1.0 : 0.15
        }
        // Tooltip hover — highlight a single hour
        if let label = hoveredBarLabel {
            return entry.label == label ? 1.0 : 0.4
        }
        // Active session segment pulses when no hover interaction is active
        if entry.isActive { return pulseState.opacity }
        return 1.0
    }

    private func barTooltip(for label: String) -> some View {
        let matching = entries.filter { $0.label == label }
        let bucketTotal = matching.reduce(0.0) { $0 + $1.value }

        return ChartTooltip {
            Text(tooltipLabels[label] ?? label)
                .font(.dataLabel)

            ForEach(matching, id: \.id) { entry in
                HStack(spacing: 6) {
                    Circle()
                        .fill(activityColorMap[entry.activity] ?? .secondary)
                        .frame(width: 8, height: 8)
                    Text(entry.activity)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(formatValue(entry.value, active: entry.isActive))
                        .font(.dataValue)
                }
            }

            let hasActive = matching.contains { $0.isActive }
            if matching.count > 1 {
                Divider()
                HStack {
                    Text("Total")
                        .font(.dataLabel)
                    Spacer()
                    Text(formatValue(bucketTotal, active: hasActive))
                        .font(.dataBoldValue)
                }
            }
        }
    }

    /// Format a value for tooltip display, using the correct unit for the period.
    private func formatValue(_ value: Double, active: Bool = false) -> String {
        if selectedPeriod == .daily {
            TimeFormatting.formatDuration(seconds: Int(value * 60), active: active)
        } else {
            TimeFormatting.formatDuration(seconds: Int(value * 3600), active: active)
        }
    }

    /// Determines whether an x-axis label should be shown for the current period.
    private func shouldShowXAxisLabel(_ label: String) -> Bool {
        switch selectedPeriod {
        case .daily:
            // Show 3am, 6am, 9am, 12pm, 3pm, 6pm, 9pm
            let visibleHours: Set<String> = [
                hourLabel(3), hourLabel(6), hourLabel(9), hourLabel(12),
                hourLabel(15), hourLabel(18), hourLabel(21),
            ]
            return visibleHours.contains(label)
        case .weekly:
            return true
        case .monthly:
            // Show 1, 7, 14, 21, 28 (skip 28 for 29-day months), and the last day
            let daysInMonth = domain.count
            var visible: Set<String> = ["1", "7", "14", "21"]
            if daysInMonth != 29 {
                visible.insert("28")
            }
            let lastDay = String(daysInMonth)
            visible.insert(lastDay)
            return visible.contains(label)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return ChartFormatters.hour.string(from: date).lowercased()
    }
}

// MARK: - Supporting Types

struct BarEntry: Identifiable {
    /// Deterministic ID so chart identity is stable during per-second active session updates.
    var id: String { "\(label)-\(activity)" }
    let label: String
    let activity: String
    let value: Double
    var isActive: Bool = false
}
