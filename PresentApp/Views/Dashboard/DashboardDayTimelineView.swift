import SwiftUI
import Charts
import PresentCore

struct DashboardDayTimelineView: View {
    let activityColorMap: [String: Color]
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var completedSessions: [(Session, Activity)] = []
    @State private var sessionSegments: [Int64: [SessionSegment]] = [:]
    @State private var hoveredActivityTitle: String? = nil
    @State private var hoveredBlock: TimelineBlock?
    @State private var hoverLocation: CGPoint = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barHeight: CGFloat = 48
    private let axisHours = stride(from: 0, through: 24, by: 3).map { $0 }
    private var startOfDay: Date { Calendar.current.startOfDay(for: Date()) }
    private let secondsInDay: Double = 24 * 60 * 60

    private var allSessions: [(Session, Activity)] {
        var result = completedSessions
        // Include active session regardless of start date (handles cross-midnight)
        if let current = appState.currentSession,
           let activity = appState.currentActivity,
           !result.contains(where: { $0.0.id == current.id }) {
            result.insert((current, activity), at: 0)
        }
        return result
    }

    private var legendItems: [(label: String, color: Color)] {
        var seen = Set<Int64>()
        var items: [(label: String, color: Color)] = []
        for (_, activity) in allSessions {
            guard let id = activity.id, seen.insert(id).inserted else { continue }
            items.append((label: activity.title, color: activityColor(activity)))
        }
        return items.sorted { $0.label < $1.label }
    }

    /// A single renderable block on the timeline, representing one contiguous active segment.
    private struct TimelineBlock: Identifiable {
        let id: String
        let start: Date
        let end: Date? // nil = live (currently running)
        let session: Session
        let activity: Activity
        let isLiveSegment: Bool // only the last open segment of a running session
    }

    /// Flat list of timeline blocks — one per segment, with gaps where pauses occurred.
    private var allBlocks: [TimelineBlock] {
        var blocks: [TimelineBlock] = []
        for (session, activity) in allSessions {
            guard let sessionId = session.id else { continue }
            if let segments = sessionSegments[sessionId], !segments.isEmpty {
                for (index, segment) in segments.enumerated() {
                    let isLast = index == segments.count - 1
                    let isLive = isLast && session.state == .running && segment.endedAt == nil
                    blocks.append(TimelineBlock(
                        id: "\(sessionId)-\(index)",
                        start: segment.startedAt,
                        end: isLive ? nil : segment.endedAt,
                        session: session,
                        activity: activity,
                        isLiveSegment: isLive
                    ))
                }
            } else {
                // Fallback: no segments loaded yet, render as single block
                blocks.append(TimelineBlock(
                    id: "fallback-\(sessionId)",
                    start: session.startedAt,
                    end: session.endedAt,
                    session: session,
                    activity: activity,
                    isLiveSegment: session.state == .running
                ))
            }
        }
        return blocks
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
                    ForEach(allBlocks) { block in
                        let x = segmentXPos(block, geo.size.width)
                        let w = segmentWidth(block, geo.size.width)
                        let color = activityColor(block.activity)
                        let isActive = block.session.id == appState.currentSession?.id
                        let dimmed = hoveredActivityTitle != nil && hoveredActivityTitle != block.activity.title

                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(color.opacity(isActive ? 1.0 : 0.75))
                            .frame(width: w, height: barHeight)
                            .offset(x: x)
                            .phaseAnimator(
                                block.isLiveSegment && !reduceMotion
                                    ? [Constants.activePulseHigh, Constants.activePulseLow]
                                    : [isActive ? 1.0 : 1.0]
                            ) { content, phase in
                                content.opacity(dimmed ? 0.2 : phase)
                            } animation: { phase in
                                phase == Constants.activePulseLow
                                    ? .easeInOut(duration: Constants.activePulseDuration).delay(Constants.activePulseDelay)
                                    : .easeInOut(duration: Constants.activePulseDuration)
                            }
                    }

                    // X-axis tick marks
                    ForEach(axisHours, id: \.self) { hour in
                        Rectangle()
                            .fill(Color.white.opacity(0.15))
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
        .task(id: "\(appState.todayActivities.map(\.activity.id))-\(appState.currentSession?.state.rawValue ?? "")") {
            await loadSessions()
        }
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
            _ = appState.timerElapsedSeconds
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
        for block in allBlocks.reversed() {
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
        return TimeFormatting.formatDuration(seconds: appState.timerElapsedSeconds)
    }

    private func tooltipTimeRange(_ session: Session) -> String {
        let start = TimeFormatting.formatTime(session.startedAt)
        if let end = session.endedAt {
            return "\(start) – \(TimeFormatting.formatTime(end))"
        }
        return "\(start) – now"
    }

    private func loadSessions() async {
        guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        guard let result = try? await appState.service.listSessions(
            from: startOfDay, to: endOfDay, type: nil, activityId: nil, includeArchived: false
        ) else { return }
        completedSessions = result

        // Fetch segments for all visible sessions (completed + active)
        var allIds = result.compactMap { $0.0.id }
        if let activeId = appState.currentSession?.id, !allIds.contains(activeId) {
            allIds.append(activeId)
        }
        sessionSegments = (try? await appState.service.segmentsForSessions(sessionIds: allIds)) ?? [:]
    }
}
