import SwiftUI
import Charts
import PresentCore

struct ReportsView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var selectedPeriod: ReportPeriod = .daily
    @State private var selectedDate: Date = Date()
    @State private var includeArchived = false
    @State private var activities: [ActivitySummary] = []
    @State private var totalSeconds: Int = 0
    @State private var sessionCount: Int = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Period picker and controls
                controlsBar

                // Summary stats
                summaryBar

                // Charts
                if !activities.isEmpty {
                    barChartCard
                    pieChartCard
                }

                // Export
                exportButton
            }
            .padding(20)
        }
        .navigationTitle("Reports")
        .task {
            await loadReport()
        }
        .onChange(of: selectedPeriod) {
            Task { await loadReport() }
        }
        .onChange(of: selectedDate) {
            Task { await loadReport() }
        }
        .onChange(of: includeArchived) {
            Task { await loadReport() }
        }
    }

    // MARK: - Controls

    private var controlsBar: some View {
        HStack {
            Picker("Period", selection: $selectedPeriod) {
                ForEach(ReportPeriod.allCases, id: \.self) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 250)

            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                .labelsHidden()

            Toggle("Include archived", isOn: $includeArchived)
                .toggleStyle(ThemedToggleStyle(tintColor: theme.accent))

            Spacer()
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 40) {
            VStack {
                Text(TimeFormatting.formatDuration(seconds: totalSeconds))
                    .font(.title.bold())
                Text("Total Time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack {
                Text("\(sessionCount)")
                    .font(.title.bold())
                Text("Sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack {
                Text("\(activities.count)")
                    .font(.title.bold())
                Text("Activities")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Charts

    private var barChartCard: some View {
        GroupBox("Time by Activity") {
            Chart(activities, id: \.activity.id) { summary in
                BarMark(
                    x: .value("Activity", summary.activity.title),
                    y: .value("Hours", Double(summary.totalSeconds) / 3600.0)
                )
                .foregroundStyle(by: .value("Activity", summary.activity.title))
            }
            .chartLegend(.hidden)
            .frame(height: 250)
            .padding(4)
        }
    }

    private var pieChartCard: some View {
        GroupBox("Time Distribution") {
            Chart(activities, id: \.activity.id) { summary in
                SectorMark(
                    angle: .value("Time", summary.totalSeconds),
                    innerRadius: .ratio(0.5),
                    angularInset: 1
                )
                .foregroundStyle(by: .value("Activity", summary.activity.title))
            }
            .frame(height: 250)
            .padding(4)
        }
    }

    // MARK: - Export

    private var exportButton: some View {
        HStack {
            Spacer()
            Button("Export CSV") {
                Task { await exportCSV() }
            }
        }
    }

    // MARK: - Data Loading

    private func loadReport() async {
        do {
            switch selectedPeriod {
            case .daily:
                let summary = try await appState.service.dailySummary(date: selectedDate, includeArchived: includeArchived)
                activities = summary.activities
                totalSeconds = summary.totalSeconds
                sessionCount = summary.sessionCount
            case .weekly:
                let summary = try await appState.service.weeklySummary(weekOf: selectedDate, includeArchived: includeArchived)
                activities = summary.activities
                totalSeconds = summary.totalSeconds
                sessionCount = summary.sessionCount
            case .monthly:
                let summary = try await appState.service.monthlySummary(monthOf: selectedDate, includeArchived: includeArchived)
                activities = summary.activities
                totalSeconds = summary.totalSeconds
                sessionCount = summary.sessionCount
            }
        } catch {
            print("Error loading report: \(error)")
        }
    }

    private func exportCSV() async {
        do {
            let calendar = Calendar.current
            let from: Date
            let to: Date

            switch selectedPeriod {
            case .daily:
                from = calendar.startOfDay(for: selectedDate)
                to = calendar.date(byAdding: .day, value: 1, to: from)!
            case .weekly:
                from = calendar.dateInterval(of: .weekOfYear, for: selectedDate)!.start
                to = calendar.date(byAdding: .day, value: 7, to: from)!
            case .monthly:
                from = calendar.dateInterval(of: .month, for: selectedDate)!.start
                to = calendar.dateInterval(of: .month, for: selectedDate)!.end
            }

            let data = try await appState.service.exportCSV(from: from, to: to, includeArchived: includeArchived)

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "present-report.csv"

            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
            }
        } catch {
            print("Error exporting CSV: \(error)")
        }
    }
}

enum ReportPeriod: String, CaseIterable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
}
