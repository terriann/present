import SwiftUI
import PresentCore

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @State private var searchText = ""
    @State private var selectedSessionType: SessionType = .work
    @State private var timerMinutes: Int = 25
    @State private var newActivityTitle = ""
    @State private var editingActivity: Activity?

    var body: some View {
        VStack(spacing: 0) {
            if appState.isSessionRunning {
                // Focused: timer + controls only
                currentSessionSection
            } else {
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

    private let menuBarSessionTypes: [SessionType] = SessionType.allCases.filter { $0 != .timebox }

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Session type tabs (timebox excluded — needs dedicated page)
            HStack(spacing: 4) {
                ForEach(menuBarSessionTypes, id: \.self) { type in
                    let isSelected = selectedSessionType == type
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedSessionType = type
                        }
                    } label: {
                        Text(SessionTypeConfig.config(for: type).displayName)
                            .font(.caption.weight(isSelected ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear, in: Capsule())
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Duration controls for rhythm/timebound
            if selectedSessionType == .rhythm {
                HStack(spacing: 4) {
                    ForEach([25, 30, 45], id: \.self) { mins in
                        let isSelected = timerMinutes == mins
                        Button {
                            timerMinutes = mins
                        } label: {
                            Text("\(mins) min")
                                .font(.caption2.weight(isSelected ? .semibold : .regular))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08), in: Capsule())
                                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            } else if selectedSessionType == .timebound {
                HStack(spacing: 4) {
                    Text("Duration:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", value: $timerMinutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 48)
                        .font(.caption)
                    Text("min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search activities...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Activity list heading
            Text("Recent Activities")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 4)

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
                    QuickStartRow(activity: activity, onTap: {
                        Task {
                            let minutes: Int? = (selectedSessionType == .rhythm || selectedSessionType == .timebound) ? timerMinutes : nil
                            await appState.startSession(activityId: activity.id!, type: selectedSessionType, timerMinutes: minutes)
                        }
                    }, onEdit: {
                        editingActivity = activity
                    })
                }
            }

            // Quick-create activity
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("New activity...", text: $newActivityTitle)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        guard !newActivityTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        Task {
                            guard let activity = try? await appState.service.createActivity(
                                CreateActivityInput(title: newActivityTitle.trimmingCharacters(in: .whitespaces))
                            ) else { return }
                            newActivityTitle = ""
                            let minutes: Int? = (selectedSessionType == .rhythm || selectedSessionType == .timebound) ? timerMinutes : nil
                            await appState.startSession(activityId: activity.id!, type: selectedSessionType, timerMinutes: minutes)
                        }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .sheet(item: $editingActivity) { activity in
            ActivityFormSheet(mode: .edit(activity))
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

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func openMainWindow() {
        NSApp.keyWindow?.close()
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
