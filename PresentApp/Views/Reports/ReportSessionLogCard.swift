import SwiftUI
import PresentCore

struct ReportSessionLogCard: View {
    let sessionEntries: [(Session, Activity)]
    let onReload: () -> Void

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
                    ForEach(Array(sessionEntries.enumerated()), id: \.element.0.id) { index, entry in
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
