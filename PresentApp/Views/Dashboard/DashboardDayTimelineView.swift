import SwiftUI
import PresentCore

struct DashboardDayTimelineView: View {
    let activityColorMap: [String: Color]
    @Environment(AppState.self) private var appState
    @State private var completedSessions: [(Session, Activity)] = []
    @State private var sessionSegments: [Int64: [SessionSegment]] = [:]
    @State private var hoveredActivityTitle: String? = nil

    private var startOfDay: Date { Calendar.current.startOfDay(for: Date()) }

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

    var body: some View {
        DayTimelineChart(
            blocks: TimelineBlock.blocks(
                from: allSessions,
                segments: sessionSegments,
                liveSessionId: appState.currentSession?.id
            ),
            activityColorMap: activityColorMap,
            referenceDate: Date(),
            liveSessionId: appState.currentSession?.id,
            timerElapsedSeconds: appState.timerElapsedSeconds,
            hoveredActivityTitle: $hoveredActivityTitle
        )
        .task(id: "\(appState.todayActivities.map(\.activity.id))-\(appState.currentSession?.state.rawValue ?? "")") {
            await loadSessions()
        }
    }

    // MARK: - Data Loading

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
