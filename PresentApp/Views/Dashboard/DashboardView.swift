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
                activityBreakdownCard
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
            Text("Current Session")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 12)

            if let activity = appState.currentActivity, let session = appState.currentSession {
                VStack(spacing: 12) {
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
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Today's Summary

    private var todaySummaryCard: some View {
        VStack(spacing: 12) {
            Text(Date.now.formatted(date: .complete, time: .omitted))
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 40) {
                StatItem(
                    title: "Total Time",
                    value: TimeFormatting.formatDuration(seconds: appState.todayTotalSeconds),
                    icon: "clock"
                )

                StatItem(
                    title: "Sessions",
                    value: "\(appState.todaySessionCount)",
                    icon: "number"
                )

                StatItem(
                    title: "Activities",
                    value: "\(appState.todayActivities.count)",
                    icon: "tray"
                )

                Spacer()
            }
        }
    }

    // MARK: - Activity Breakdown

    private var activityBreakdownCard: some View {
        GroupBox {
            Text("Activity Breakdown")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 12)

            if appState.todayActivities.isEmpty {
                ContentUnavailableView(
                    "No Activity Yet",
                    systemImage: "chart.bar",
                    description: Text("Start a session to see your activity breakdown.")
                )
                .emptyStateStyle()
            } else {
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
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }
}
