import SwiftUI
import PresentCore

struct ReportSessionLogCard: View {
    let sessionEntries: [(Session, Activity)]
    let onReload: () -> Void

    @State private var searchText = ""

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
                    // Search bar
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
                }
            }
        }
    }
}
