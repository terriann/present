import SwiftUI
import PresentCore

struct ReportActivityBreakdownCard: View {
    let sessionEntries: [(Session, Activity)]
    let onReload: () -> Void

    @Environment(ThemeManager.self) private var theme
    @State private var searchText = ""
    @State private var viewMode: ViewMode = .chronological
    @State private var sortOrder: ActivitySortOrder = .timeSpent
    @State private var expandedActivities: Set<Int64> = []

    private enum ViewMode: String, CaseIterable {
        case chronological
        case groupedByActivity

        var displayName: String {
            switch self {
            case .chronological: "Chronological"
            case .groupedByActivity: "By Activity"
            }
        }
    }

    // MARK: - Filtered Entries

    private var filteredEntries: [(Session, Activity)] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return sessionEntries }
        return sessionEntries.filter { session, activity in
            if let note = session.note, note.lowercased().contains(trimmed) { return true }
            if let ticketId = session.ticketId, ticketId.lowercased().contains(trimmed) { return true }
            if activity.title.lowercased().contains(trimmed) { return true }
            return false
        }
    }

    // MARK: - Grouped Entries

    private var groupedEntries: [(activity: Activity, sessions: [(Session, Activity)], totalSeconds: Int)] {
        let entries = filteredEntries
        var groups: [Int64: (activity: Activity, sessions: [(Session, Activity)])] = [:]
        var order: [Int64] = []

        for entry in entries {
            let activityId = entry.1.id ?? -1
            if groups[activityId] == nil {
                groups[activityId] = (activity: entry.1, sessions: [])
                order.append(activityId)
            }
            groups[activityId]?.sessions.append(entry)
        }

        var result = order.compactMap { id -> (activity: Activity, sessions: [(Session, Activity)], totalSeconds: Int)? in
            guard let group = groups[id] else { return nil }
            // Sort sessions within group by startedAt ascending (chronological)
            let sorted = group.sessions.sorted { $0.0.startedAt < $1.0.startedAt }
            // Round each session to the minute before summing
            let total = sorted.reduce(0) { sum, entry in
                sum + TimeFormatting.floorToMinute(entry.0.durationSeconds ?? 0)
            }
            return (activity: group.activity, sessions: sorted, totalSeconds: total)
        }

        switch sortOrder {
        case .timeSpent:
            result.sort { $0.totalSeconds > $1.totalSeconds }
        case .mostRecent:
            result.sort { a, b in
                let aLatest = a.sessions.last?.0.startedAt ?? .distantPast
                let bLatest = b.sessions.last?.0.startedAt ?? .distantPast
                return aLatest > bLatest
            }
        case .alphabetical:
            result.sort { $0.activity.title.localizedCaseInsensitiveCompare($1.activity.title) == .orderedAscending }
        }

        return result
    }

    // MARK: - Body

    var body: some View {
        ChartCard(title: "Session Log") {
            if sessionEntries.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "list.bullet",
                    description: Text("No sessions recorded for this period.")
                )
                .emptyStateStyle()
            } else {
                VStack(spacing: 0) {
                    searchBar
                    Divider()
                    controlsBar
                    Divider()

                    let entries = filteredEntries
                    if entries.isEmpty {
                        ContentUnavailableView(
                            "No Matches",
                            systemImage: "magnifyingglass",
                            description: Text("No sessions match \"\(searchText)\".")
                        )
                        .emptyStateStyle()
                    } else {
                        switch viewMode {
                        case .chronological:
                            chronologicalView(entries: entries)
                        case .groupedByActivity:
                            groupedView
                        }
                    }
                }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Search notes, tickets, activities...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.subheadline)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Constants.spacingCard)
        .padding(.vertical, Constants.spacingCompact)
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        HStack {
            Picker("View", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Spacer()

            if viewMode == .groupedByActivity {
                Picker("Sort", selection: $sortOrder) {
                    ForEach(ActivitySortOrder.allCases, id: \.self) { order in
                        Text(order.displayName).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
        .padding(.horizontal, Constants.spacingCard)
        .padding(.vertical, Constants.spacingCompact)
    }

    // MARK: - Chronological View

    private func chronologicalView(entries: [(Session, Activity)]) -> some View {
        ForEach(Array(entries.enumerated()), id: \.element.0.id) { index, entry in
            SessionRow(session: entry.0, activityTitle: entry.1.title)
                .padding(.horizontal, Constants.spacingCard)
                .padding(.vertical, Constants.spacingCompact)
                .background(index.isMultiple(of: 2) ? Color.clear : Color.gray.opacity(0.08))
                .contentShape(Rectangle())
                .sessionContextMenu(session: entry.0, activityTitle: entry.1.title) {
                    onReload()
                }
        }
    }

    // MARK: - Grouped View

    private var groupedView: some View {
        let groups = groupedEntries
        return VStack(spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.element.activity.id) { index, group in
                let activityId = group.activity.id ?? -1
                let isExpanded = expandedActivities.contains(activityId)
                let sessionCount = group.sessions.count

                VStack(spacing: 0) {
                    // Activity header
                    HStack {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))

                        Text(group.activity.title)
                            .font(.title3)
                            .lineLimit(1)

                        Text("\(sessionCount) \(sessionCount == 1 ? "session" : "sessions")")
                            .font(.body)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(TimeFormatting.formatDuration(seconds: group.totalSeconds))
                            .font(.durationValue)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, Constants.spacingCompact)
                    .padding(.horizontal, Constants.spacingCard)
                    .background(index.isMultiple(of: 2) ? Color.clear : Color.gray.opacity(0.08))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAdaptiveAnimation(.easeInOut(duration: 0.2)) {
                            if isExpanded {
                                expandedActivities.remove(activityId)
                            } else {
                                expandedActivities.insert(activityId)
                            }
                        }
                    }

                    // Expanded sessions
                    if isExpanded {
                        ForEach(group.sessions, id: \.0.id) { entry in
                            SessionRow(session: entry.0, activityTitle: entry.1.title)
                                .padding(.horizontal, Constants.spacingCard)
                                .padding(.vertical, Constants.spacingCompact)
                                .padding(.leading, 20)
                                .background(Color.gray.opacity(0.04))
                                .contentShape(Rectangle())
                                .sessionContextMenu(session: entry.0, activityTitle: entry.1.title) {
                                    onReload()
                                }
                        }
                    }
                }
            }
        }
    }
}
