import SwiftUI
import PresentCore

struct LogView: View {
    @Environment(AppState.self) private var appState
    @State private var sessionEntries: [(Session, Activity)] = []
    @State private var searchText = ""
    @State private var selectedType: SessionType?
    @State private var dateFrom: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var dateTo: Date = Date()

    var body: some View {
        VStack(spacing: 0) {
            LogFilterBar(
                searchText: $searchText,
                selectedType: $selectedType,
                dateFrom: $dateFrom,
                dateTo: $dateTo,
                onRefresh: { await loadSessions() }
            )

            Divider()

            if filteredEntries.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "list.bullet.clipboard",
                    description: Text("Completed sessions will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 40)
            } else {
                List(filteredEntries, id: \.0.id) { session, activity in
                    SessionRow(session: session, activityTitle: activity.title)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Log")
        .task {
            await loadSessions()
        }
        .onChange(of: selectedType) {
            Task { await loadSessions() }
        }
        .onChange(of: dateFrom) {
            Task { await loadSessions() }
        }
        .onChange(of: dateTo) {
            Task { await loadSessions() }
        }
    }

    private var filteredEntries: [(Session, Activity)] {
        if searchText.isEmpty {
            return sessionEntries
        }
        return sessionEntries.filter { _, activity in
            activity.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func loadSessions() async {
        do {
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: dateTo))!
            sessionEntries = try await appState.service.listSessions(
                from: Calendar.current.startOfDay(for: dateFrom),
                to: endOfDay,
                type: selectedType,
                activityId: nil,
                includeArchived: true
            )
        } catch {
            appState.showError(error, context: "Could not load sessions")
        }
    }
}
