import SwiftUI
import PresentCore

struct ActivitiesListView: View {
    @Environment(AppState.self) private var appState
    @State private var showingCreateSheet = false
    @State private var showArchived = false
    @State private var selectedActivity: Activity?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Toggle("Show archived", isOn: $showArchived)
                Spacer()
                Text("\(displayedActivities.count) activities")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    showingCreateSheet = true
                } label: {
                    Label("New Activity", systemImage: "plus")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            if displayedActivities.isEmpty {
                ContentUnavailableView(
                    "No Activities",
                    systemImage: "tray",
                    description: Text("Create an activity to start tracking time.")
                )
            } else {
                List(displayedActivities, selection: $selectedActivity) { activity in
                    ActivityRow(activity: activity)
                        .tag(activity)
                }
            }
        }
        .navigationTitle("Activities")
        .sheet(isPresented: $showingCreateSheet) {
            ActivityFormSheet(mode: .create)
        }
        .task {
            await appState.refreshAll()
        }
        .onChange(of: showArchived) {
            Task { await loadActivities() }
        }
    }

    private var displayedActivities: [Activity] {
        if showArchived {
            return appState.allActivities
        }
        return appState.allActivities.filter { !$0.isArchived }
    }

    private func loadActivities() async {
        await appState.refreshAll()
    }
}

struct ActivityRow: View {
    let activity: Activity

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(activity.title)
                        .font(.body.bold())

                    if activity.isArchived {
                        Text("Archived")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.2), in: Capsule())
                    }
                }

                if let externalId = activity.externalId, !externalId.isEmpty {
                    Text(externalId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(TimeFormatting.formatDate(activity.updatedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
