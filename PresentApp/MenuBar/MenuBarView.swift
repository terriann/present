import SwiftUI
import PresentCore

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var showingSessionTypeSheet = false
    @State private var selectedActivity: Activity?

    var body: some View {
        VStack(spacing: 0) {
            if appState.isSessionActive {
                currentSessionSection
            } else {
                idleSection
            }

            Divider()

            quickStartSection

            Divider()

            bottomBar
        }
        .frame(width: 320)
    }

    // MARK: - Current Session

    private var currentSessionSection: some View {
        VStack(spacing: 12) {
            if let activity = appState.currentActivity, let session = appState.currentSession {
                VStack(spacing: 4) {
                    Text(activity.title)
                        .font(.headline)
                        .lineLimit(1)

                    Text(SessionTypeConfig.config(for: session.sessionType).displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(appState.formattedTimerValue)
                    .font(.system(size: 36, weight: .light, design: .monospaced))
                    .contentTransition(.numericText())

                SessionControls()
            }
        }
        .padding()
    }

    // MARK: - Idle

    private var idleSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text("No active session")
                .font(.headline)

            if appState.todaySessionCount > 0 {
                Text("\(appState.todaySessionCount) sessions today \u{2022} \(TimeFormatting.formatDuration(seconds: appState.todayTotalSeconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Quick Start

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search activities...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Activity list
            let activities = filteredActivities
            if activities.isEmpty && !searchText.isEmpty {
                Text("No matching activities")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            } else {
                ForEach(activities) { activity in
                    QuickStartRow(activity: activity) {
                        selectedActivity = activity
                        showingSessionTypeSheet = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingSessionTypeSheet) {
            if let activity = selectedActivity {
                SessionTypePickerSheet(activity: activity)
            }
        }
    }

    private var filteredActivities: [Activity] {
        let source = searchText.isEmpty ? appState.recentActivities : appState.allActivities
        if searchText.isEmpty {
            return source
        }
        return source.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button("Open Present") {
                openMainWindow()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func openMainWindow() {
        if let url = URL(string: "present://open") {
            NSWorkspace.shared.open(url)
        }
        // Fallback: use environment to open window
        NSApplication.shared.activate(ignoringOtherApps: true)
        for window in NSApplication.shared.windows where window.title == "Present" {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}
