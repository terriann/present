import SwiftUI
import PresentCore

/// Timeline card for the daily report view, wrapping the shared DayTimelineChart.
struct ReportDayTimelineCard: View {
    let sessionEntries: [(Session, Activity)]
    let sessionSegments: [Int64: [SessionSegment]]
    let activityColorMap: [String: Color]
    let referenceDate: Date

    @Environment(AppState.self) private var appState
    @State private var hoveredActivityTitle: String? = nil

    /// Whether the report is viewing today (enables live session support).
    private var isToday: Bool {
        Calendar.current.isDateInToday(referenceDate)
    }

    private var allSessions: [(Session, Activity)] {
        var result = sessionEntries
        // Include active session when viewing today (handles cross-midnight)
        if isToday,
           let current = appState.currentSession,
           let activity = appState.currentActivity,
           !result.contains(where: { $0.0.id == current.id }) {
            result.insert((current, activity), at: 0)
        }
        return result
    }

    private var liveSessionId: Int64? {
        isToday ? appState.currentSession?.id : nil
    }

    var body: some View {
        ChartCard(title: "Timeline") {
            DayTimelineChart(
                blocks: TimelineBlock.blocks(
                    from: allSessions,
                    segments: sessionSegments,
                    liveSessionId: liveSessionId
                ),
                activityColorMap: activityColorMap,
                referenceDate: referenceDate,
                liveSessionId: liveSessionId,
                timerElapsedSeconds: isToday ? appState.timerElapsedSeconds : 0,
                hoveredActivityTitle: $hoveredActivityTitle
            )
            .padding(.horizontal, Constants.spacingCard)
            .padding(.bottom, Constants.spacingCard)
        }
    }
}
