import SwiftUI
import PresentCore

/// A single renderable block on the timeline, representing one contiguous active segment.
struct TimelineBlock: Identifiable {
    let id: String
    let start: Date
    let end: Date? // nil = live (currently running)
    let session: Session
    let activity: Activity
    let isLiveSegment: Bool // only the last open segment of a running session

    /// Build timeline blocks from session/activity pairs and their segments.
    ///
    /// Adjacent segments with less than 90 seconds between them are coalesced
    /// into a single continuous block. Short pauses are below the timeline's
    /// display resolution and would otherwise create visual clutter.
    static func blocks(
        from sessions: [(Session, Activity)],
        segments: [Int64: [SessionSegment]],
        liveSessionId: Int64?
    ) -> [TimelineBlock] {
        var result: [TimelineBlock] = []
        for (session, activity) in sessions {
            guard let sessionId = session.id else { continue }
            if let segs = segments[sessionId], !segs.isEmpty {
                // Coalesce segments with < 90s gaps
                var coalescedStart = segs[0].startedAt
                var coalescedEnd = segs[0].endedAt
                var blockIndex = 0

                for i in 1..<segs.count {
                    let gap: TimeInterval
                    if let prevEnd = coalescedEnd {
                        gap = segs[i].startedAt.timeIntervalSince(prevEnd)
                    } else {
                        gap = 0 // previous segment is still open (live)
                    }

                    if gap < 90 {
                        // Merge: extend the coalesced block
                        coalescedEnd = segs[i].endedAt ?? coalescedEnd
                    } else {
                        // Emit the current coalesced block
                        result.append(TimelineBlock(
                            id: "\(sessionId)-\(blockIndex)",
                            start: coalescedStart,
                            end: coalescedEnd,
                            session: session,
                            activity: activity,
                            isLiveSegment: false
                        ))
                        blockIndex += 1
                        coalescedStart = segs[i].startedAt
                        coalescedEnd = segs[i].endedAt
                    }
                }

                // Emit the final coalesced block
                let isLastSegmentLive = segs.last?.endedAt == nil && session.state == .running
                result.append(TimelineBlock(
                    id: "\(sessionId)-\(blockIndex)",
                    start: coalescedStart,
                    end: isLastSegmentLive ? nil : coalescedEnd,
                    session: session,
                    activity: activity,
                    isLiveSegment: isLastSegmentLive
                ))
            } else {
                // Fallback: no segments loaded yet, render as single block
                result.append(TimelineBlock(
                    id: "fallback-\(sessionId)",
                    start: session.startedAt,
                    end: session.endedAt,
                    session: session,
                    activity: activity,
                    isLiveSegment: session.id == liveSessionId && session.state == .running
                ))
            }
        }
        return result
    }
}

/// Shared day timeline chart rendering — a horizontal bar showing colored session blocks
/// on a 24-hour track with hover tooltips and a legend.
struct DayTimelineChart: View {
    @Environment(ThemeManager.self) private var theme
    let blocks: [TimelineBlock]
    let activityColorMap: [String: Color]
    let referenceDate: Date
    let liveSessionId: Int64?
    let timerElapsedSeconds: Int
    @Binding var hoveredActivityTitle: String?

    @State private var hoveredBlock: TimelineBlock?
    @State private var hoverLocation: CGPoint = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barHeight: CGFloat = 48
    private let axisHours = stride(from: 0, through: 24, by: 3).map { $0 }
    private var startOfDay: Date { Calendar.current.startOfDay(for: referenceDate) }
    private let secondsInDay: Double = 24 * 60 * 60

    private var legendItems: [(label: String, color: Color)] {
        var seen = Set<Int64>()
        var items: [(label: String, color: Color)] = []
        for block in blocks {
            guard let id = block.activity.id, seen.insert(id).inserted else { continue }
            items.append((label: block.activity.title, color: activityColor(block.activity)))
        }
        return items.sorted { $0.label < $1.label }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.spacingCompact) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track background (extended past tick marks so corners don't clip them)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.12))
                        .frame(width: geo.size.width + 16, height: barHeight)
                        .offset(x: -8)

                    // Segment blocks (one per contiguous active period)
                    ForEach(blocks) { block in
                        let x = segmentXPos(block, geo.size.width)
                        let w = segmentWidth(block, geo.size.width)
                        let color = activityColor(block.activity)
                        let isActive = block.session.id == liveSessionId
                        let dimmed = hoveredActivityTitle != nil && hoveredActivityTitle != block.activity.title

                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(color.opacity(isActive ? 1.0 : 0.75))
                            // Apply pulse before layout modifiers so phaseAnimator
                            // only animates opacity, not frame/offset during resize.
                            .activePulse(isActive: block.isLiveSegment && !dimmed, reduceMotion: reduceMotion)
                            .frame(width: w, height: barHeight)
                            .offset(x: x)
                            .opacity(dimmed ? 0.2 : 1.0)
                    }

                    // X-axis tick marks
                    ForEach(axisHours, id: \.self) { hour in
                        Rectangle()
                            .fill(theme.constantWhite.opacity(0.15))
                            .frame(width: 1, height: barHeight)
                            .offset(x: CGFloat(hour) / 24.0 * geo.size.width)
                    }
                }
                .frame(height: barHeight)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        hoverLocation = point
                        let match = blockAt(x: point.x, width: geo.size.width)
                        hoveredBlock = match
                        hoveredActivityTitle = match?.activity.title
                    case .ended:
                        hoveredBlock = nil
                        hoveredActivityTitle = nil
                    }
                }
                .overlay {
                    if let block = hoveredBlock {
                        let midX = segmentXPos(block, geo.size.width)
                            + segmentWidth(block, geo.size.width) / 2
                        let clampedX = min(max(90, midX), geo.size.width - 90)
                        timelineTooltip(session: block.session, activity: block.activity)
                            .fixedSize()
                            .position(x: clampedX, y: -36)
                    }
                }

                // X-axis labels
                ZStack(alignment: .topLeading) {
                    ForEach(axisHours, id: \.self) { hour in
                        if hour == 24 {
                            Text(axisLabel(hour))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        } else {
                            Text(axisLabel(hour))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .offset(x: max(0, CGFloat(hour) / 24.0 * geo.size.width - 10))
                        }
                    }
                }
                .frame(height: 14)
                .offset(y: barHeight + 2)
            }
            .frame(height: barHeight + 16)

            // Legend
            if !legendItems.isEmpty {
                HoverableChartLegend(items: legendItems, hoveredLabel: $hoveredActivityTitle)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Day timeline")
        .accessibilityValue(timelineAccessibilityValue)
    }

    // MARK: - Accessibility

    private var timelineAccessibilityValue: String {
        var grouped: [String: TimeInterval] = [:]
        for block in blocks {
            let effectiveStart = max(block.start, startOfDay)
            let end = block.end ?? Date()
            let duration = max(0, end.timeIntervalSince(effectiveStart))
            grouped[block.activity.title, default: 0] += duration
        }
        let sorted = grouped.sorted { $0.value > $1.value }
        return sorted.map { "\($0.key): \(TimeFormatting.formatDuration(seconds: Int($0.value)))" }
            .joined(separator: ", ")
    }

    // MARK: - Helpers

    private func segmentXPos(_ block: TimelineBlock, _ width: CGFloat) -> CGFloat {
        // Clamp to start of day so cross-midnight segments begin at x=0
        let effectiveStart = max(block.start, startOfDay)
        let offset = effectiveStart.timeIntervalSince(startOfDay)
        return CGFloat(offset / secondsInDay) * width
    }

    private func segmentWidth(_ block: TimelineBlock, _ width: CGFloat) -> CGFloat {
        let effectiveStart = max(block.start, startOfDay)
        let end: Date
        if let segEnd = block.end {
            end = segEnd
        } else {
            // Live segment: read timerElapsedSeconds to drive per-second re-render
            _ = timerElapsedSeconds
            end = Date()
        }
        let duration = max(1, end.timeIntervalSince(effectiveStart))
        return max(4, CGFloat(duration / secondsInDay) * width)
    }

    private func activityColor(_ activity: Activity) -> Color {
        activityColorMap[activity.title] ?? .secondary
    }

    private func axisLabel(_ hour: Int) -> String {
        switch hour {
        case 0, 24: return "12am"
        case 12: return "12pm"
        default: return hour < 12 ? "\(hour)am" : "\(hour - 12)pm"
        }
    }

    private func blockAt(x: CGFloat, width: CGFloat) -> TimelineBlock? {
        for block in blocks.reversed() {
            let sx = segmentXPos(block, width)
            let sw = segmentWidth(block, width)
            if x >= sx && x <= sx + sw {
                return block
            }
        }
        return nil
    }

    @ViewBuilder
    private func timelineTooltip(session: Session, activity: Activity) -> some View {
        ChartTooltip {
            Text(activity.title)
                .font(.caption)
                .fontWeight(.semibold)

            Text(SessionTypeConfig.config(for: session.sessionType).displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(tooltipDuration(session))
                .font(.caption)
                .monospacedDigit()

            Text(tooltipTimeRange(session))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func tooltipDuration(_ session: Session) -> String {
        if let dur = session.durationSeconds {
            return TimeFormatting.formatDuration(seconds: dur)
        }
        return TimeFormatting.formatDuration(seconds: timerElapsedSeconds)
    }

    private func tooltipTimeRange(_ session: Session) -> String {
        let start = TimeFormatting.formatTime(session.startedAt)
        if let end = session.endedAt {
            return "\(start) – \(TimeFormatting.formatTime(end))"
        }
        return "\(start) – now"
    }
}
