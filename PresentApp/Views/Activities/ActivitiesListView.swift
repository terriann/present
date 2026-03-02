import SwiftUI
import PresentCore

struct ActivitiesListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var activities: [Activity] = []
    @State private var showingCreateSheet = false
    @State private var showArchived = false
    @State private var selectedActivity: Activity?
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {

            // Toolbar
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("Search activities...", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .accessibilityLabel("Search activities")
                }
                .padding(6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: 200)

                Toggle("Show archived", isOn: $showArchived)
                    .toggleStyle(ThemedToggleStyle(tintColor: theme.accent))

                Spacer()

                Text("\(displayedActivities.filter { !$0.isSystem }.count) activities")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    showingCreateSheet = true
                } label: {
                    Label("New Activity", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding(.horizontal, Constants.spacingToolbar)
            .padding(.vertical, Constants.spacingCompact)

            Divider()

            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Activity list
                    Group {
                        if displayedActivities.isEmpty {
                            ContentUnavailableView(
                                "No Activities",
                                systemImage: "tray",
                                description: Text("Create an activity to start tracking time.")
                            )
                            .emptyStateStyle()
                        } else {
                            List {
                                ForEach(displayedActivities) { activity in
                                    Button {
                                        selectedActivity = activity
                                    } label: {
                                        ActivityRow(activity: activity)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(selectedActivity == activity ? theme.accent.opacity(0.15) : Color.clear)
                                    )
                                }
                            }
                            .listStyle(.inset)
                        }
                    }
                    .frame(width: geometry.size.width * 0.35)

                    Divider()

                    // Detail view
                    if let activity = selectedActivity {
                        ActivitiesDetailView(activity: activity)
                            .id(activity.id)
                            .environment(appState)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView(
                            "Select an Activity",
                            systemImage: "tray",
                            description: Text("Choose an activity from the list to view its details.")
                        )
                        .emptyStateStyle()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Activities")
        .sheet(isPresented: $showingCreateSheet) {
            ActivitiesFormSheet(mode: .create)
        }
        .task { await loadActivities() }
        .onChange(of: appState.refreshCounter) {
            Task { await loadActivities() }
        }
        .onChange(of: showArchived) {
            // No need to re-fetch — displayedActivities filters locally
        }
        .onAppear {
            isSearchFocused = true
            handleNavigationRequest()
        }
        .onChange(of: appState.navigateToActivityId) {
            handleNavigationRequest()
        }
    }

    // MARK: - Data Loading

    private func loadActivities() async {
        do {
            activities = try await appState.service.listActivities(
                includeArchived: true, includeSystem: true
            )
        } catch {
            // Fail silently — list stays as-is
        }
    }

    // MARK: - Navigation

    private func handleNavigationRequest() {
        guard let targetId = appState.navigateToActivityId else { return }
        appState.navigateToActivityId = nil
        // Try local list first, fall back to direct DB lookup
        if let match = activities.first(where: { $0.id == targetId }) {
            selectedActivity = match
        } else {
            Task {
                if let activity = try? await appState.service.getActivity(id: targetId) {
                    selectedActivity = activity
                }
            }
        }
    }

    // MARK: - Filtering

    private var displayedActivities: [Activity] {
        var filtered = activities
        if !showArchived {
            filtered = filtered.filter { !$0.isArchived }
        }
        if !searchText.isEmpty {
            filtered = filtered.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        return filtered
    }
}

struct ActivityRow: View {
    let activity: Activity
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    if activity.isSystem {
                        Image(systemName: "cup.and.saucer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(activity.title)
                        .font(.body.bold())

                    if activity.isSystem {
                        Text("System")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.accent.opacity(0.2), in: Capsule())
                    }

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

            if !activity.isSystem {
                Text(TimeFormatting.formatDate(activity.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
