import SwiftUI
import PresentCore

struct ActivitiesListView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var activities: [Activity] = []
    @State private var activityTags: [Int64: [Tag]] = [:]
    @State private var showArchived = false
    @State private var selectedActivity: Activity?
    @State private var searchText = ""
    @State private var newlyCreatedActivityId: Int64?
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
                    Task { await createAndSelectActivity() }
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
                            activityList
                        }
                    }
                    .frame(width: geometry.size.width * 0.35)

                    Divider()

                    // Detail view
                    if let activity = selectedActivity {
                        ActivitiesDetailView(
                            activity: activity,
                            tagColorMap: tagColorMap,
                            startInEditMode: activity.id == newlyCreatedActivityId,
                            onDelete: { selectedActivity = nil }
                        )
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

    // MARK: - Activity List

    private var activityList: some View {
        List {
            ForEach(groupedActivities) { section in
                Section {
                    ForEach(section.activities) { activity in
                        Button {
                            selectedActivity = activity
                        } label: {
                            ActivityRow(
                                activity: activity,
                                tags: activityTags[activity.id ?? 0] ?? [],
                                tagColorMap: tagColorMap
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedActivity?.id == activity.id
                                    ? theme.accent.opacity(0.2)
                                    : Color.clear)
                                .padding(.horizontal, Constants.spacingTight)
                        )
                    }
                } header: {
                    if !section.title.isEmpty {
                        Text(section.title)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Data Loading

    private func loadActivities() async {
        do {
            activities = try await appState.listActivities(
                includeArchived: true, includeSystem: true
            )
            let ids = activities.compactMap(\.id)
            if !ids.isEmpty {
                activityTags = try await appState.tagsForActivities(activityIds: ids)
            }
        } catch {
            // Fail silently — list stays as-is
        }
    }

    private func createAndSelectActivity() async {
        do {
            let activity = try await appState.createActivity(
                CreateActivityInput(title: "Untitled Activity")
            )
            newlyCreatedActivityId = activity.id
            await loadActivities()
            selectedActivity = activities.first(where: { $0.id == activity.id })
            await appState.refreshAll()
        } catch {
            appState.showError(error, context: "Could not create activity")
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
                if let activity = try? await appState.getActivity(id: targetId) {
                    selectedActivity = activity
                }
            }
        }
    }

    // MARK: - Tag Colors

    private var tagColorMap: [String: Color] {
        let palette = ThemeManager.chartColors(for: theme.activePalette)
        let assignedNames = Set(activityTags.values.flatMap { $0 }.map(\.name))
        let sortedNames = assignedNames.sorted()
        return Dictionary(uniqueKeysWithValues: sortedNames.enumerated().map { index, name in
            (name, palette[index % palette.count])
        })
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

    // MARK: - Grouping

    private var groupedActivities: [ActivitySection] {
        let all = displayedActivities
        let user = all.filter { !$0.isSystem }
        let system = all.filter { $0.isSystem }

        var sections: [ActivitySection] = []

        if !user.isEmpty {
            sections.append(ActivitySection(id: "user", title: "", activities: user))
        }

        if !system.isEmpty {
            sections.append(ActivitySection(id: "system", title: "System", activities: system))
        }

        return sections
    }
}

// MARK: - ActivitySection

private struct ActivitySection: Identifiable {
    let id: String
    let title: String
    let activities: [Activity]
}

struct ActivityRow: View {
    let activity: Activity
    let tags: [Tag]
    let tagColorMap: [String: Color]
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.spacingTight) {
            // MARK: - Title row
            HStack {
                if activity.isSystem {
                    Image(systemName: "cup.and.saucer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(activity.title)
                    .font(.body.bold())
                    .lineLimit(1)
                    .truncationMode(.tail)

                if activity.isArchived {
                    Text("Archived")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.2), in: Capsule())
                }
            }

            // MARK: - Subtitle row (notes indicator, external ID, tags)
            if hasSubtitle {
                HStack(spacing: Constants.spacingTight) {
                    if activity.notes.map({ !$0.isEmpty }) == true {
                        Image(systemName: "doc.text")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Has notes")
                    }

                    if let externalId = activity.externalId, !externalId.isEmpty {
                        Text(externalId)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    ForEach(tags) { tag in
                        let color = tagColorMap[tag.name] ?? .secondary
                        Text(tag.name)
                            .font(.caption2)
                            .foregroundStyle(color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(color.opacity(0.15), in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, Constants.spacingTight)
        .frame(minHeight: Constants.activityRowMinHeight, alignment: .top)
    }

    // MARK: - Helpers

    private var hasSubtitle: Bool {
        !tags.isEmpty
            || activity.externalId.map({ !$0.isEmpty }) == true
            || activity.notes.map({ !$0.isEmpty }) == true
    }
}
