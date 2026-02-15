import SwiftUI
import PresentCore

struct LogView: View {
    @Environment(AppState.self) private var appState
    @State private var sessions: [Session] = []
    @State private var searchText = ""
    @State private var selectedType: SessionType?
    @State private var dateFrom: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var dateTo: Date = Date()

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            LogFilterBar(
                searchText: $searchText,
                selectedType: $selectedType,
                dateFrom: $dateFrom,
                dateTo: $dateTo,
                onRefresh: { await loadSessions() }
            )

            Divider()

            if sessions.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "list.bullet.clipboard",
                    description: Text("Completed sessions will appear here.")
                )
            } else {
                List(sessions) { session in
                    SessionRow(session: session, activityTitle: activityTitle(for: session))
                }
            }
        }
        .navigationTitle("Log")
        .task {
            await loadSessions()
        }
    }

    private func activityTitle(for session: Session) -> String {
        appState.allActivities.first { $0.id == session.activityId }?.title ?? "Unknown"
    }

    private func loadSessions() async {
        do {
            let summary = try await appState.service.dailySummary(date: Date(), includeArchived: true)
            // For now, load today's data — full filtering will be added in Phase 3
            _ = summary
        } catch {
            print("Error loading sessions: \(error)")
        }
    }
}
