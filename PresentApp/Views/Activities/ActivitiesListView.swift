import SwiftUI
import PresentCore

struct ActivitiesListView: View {
    @Environment(AppState.self) private var appState
    @State private var showingCreateSheet = false
    @State private var showArchived = false
    @State private var selectedActivity: Activity?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search activities...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: 200)

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

            HSplitView {
                // Activity list
                if displayedActivities.isEmpty {
                    ContentUnavailableView(
                        "No Activities",
                        systemImage: "tray",
                        description: Text("Create an activity to start tracking time.")
                    )
                    .frame(minWidth: 250)
                } else {
                    List(displayedActivities, selection: $selectedActivity) { activity in
                        ActivityRow(activity: activity)
                            .tag(activity)
                    }
                    .frame(minWidth: 250, maxWidth: 350)
                }

                // Detail view
                if let activity = selectedActivity {
                    ActivityDetailView(activity: activity)
                        .id(activity.id)
                        .environment(appState)
                } else {
                    ContentUnavailableView(
                        "Select an Activity",
                        systemImage: "tray",
                        description: Text("Choose an activity from the list to view its details.")
                    )
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
            Task { await appState.refreshAll() }
        }
    }

    private var displayedActivities: [Activity] {
        var activities = appState.allActivities
        if !showArchived {
            activities = activities.filter { !$0.isArchived }
        }
        if !searchText.isEmpty {
            activities = activities.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        return activities
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
