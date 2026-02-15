import SwiftUI
import PresentCore

struct DashboardView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Current session
                if appState.isSessionActive {
                    currentSessionCard
                }

                // Today's summary
                todaySummaryCard

                // Activity breakdown
                if !appState.todayActivities.isEmpty {
                    activityBreakdownCard
                }
            }
            .padding(20)
        }
        .navigationTitle("Dashboard")
        .alert(appState.isLongBreak ? "Time for a Long Break!" : "Take a Short Break",
               isPresented: Bindable(appState).showBreakSuggestion) {
            Button("OK") { appState.dismissBreakSuggestion() }
        } message: {
            Text("You've earned a \(appState.suggestedBreakMinutes)-minute break. Step away and recharge.")
        }
    }

    // MARK: - Current Session Card

    private var currentSessionCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                if let activity = appState.currentActivity, let session = appState.currentSession {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(activity.title)
                                .font(.title3.bold())

                            Text(SessionTypeConfig.config(for: session.sessionType).displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(appState.formattedTimerValue)
                            .font(.system(size: 42, weight: .light, design: .monospaced))
                            .contentTransition(.numericText())
                    }

                    SessionControls()
                }
            }
            .padding(4)
        } label: {
            Label("Current Session", systemImage: "play.circle")
        }
    }

    // MARK: - Today's Summary

    private var todaySummaryCard: some View {
        GroupBox {
            HStack(spacing: 40) {
                statItem(
                    title: "Total Time",
                    value: TimeFormatting.formatDuration(seconds: appState.todayTotalSeconds),
                    icon: "clock"
                )

                statItem(
                    title: "Sessions",
                    value: "\(appState.todaySessionCount)",
                    icon: "number"
                )

                statItem(
                    title: "Activities",
                    value: "\(appState.todayActivities.count)",
                    icon: "tray"
                )

                Spacer()
            }
            .padding(4)
        } label: {
            Label("Today", systemImage: "calendar")
        }
    }

    private func statItem(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2.bold())

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Activity Breakdown

    private var activityBreakdownCard: some View {
        GroupBox {
            VStack(spacing: 0) {
                ForEach(appState.todayActivities, id: \.activity.id) { summary in
                    HStack {
                        Text(summary.activity.title)
                            .lineLimit(1)

                        Spacer()

                        Text("\(summary.sessionCount) sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(TimeFormatting.formatDuration(seconds: summary.totalSeconds))
                            .font(.body.monospacedDigit())
                            .frame(width: 80, alignment: .trailing)
                    }
                    .padding(.vertical, 6)

                    if summary.activity.id != appState.todayActivities.last?.activity.id {
                        Divider()
                    }
                }
            }
            .padding(4)
        } label: {
            Label("Activity Breakdown", systemImage: "chart.bar")
        }
    }
}
