import SwiftUI
import PresentCore

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var selectedTab = SettingsTab.general

    static let openCLITabNotification = Notification.Name("openCLITab")

    enum SettingsTab: String, CaseIterable {
        case general, cli, sessions, notifications, about

        var label: String {
            switch self {
            case .general: "General"
            case .cli: "CLI"
            case .sessions: "Sessions"
            case .notifications: "Notifications"
            case .about: "About"
            }
        }

        var icon: String {
            switch self {
            case .general: "gear"
            case .cli: "terminal"
            case .sessions: "timer"
            case .notifications: "bell"
            case .about: "info.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom tab bar
            HStack(spacing: 2) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.title2)
                            Text(tab.label)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab ? theme.primary.opacity(0.15) : Color.clear)
                        )
                        .foregroundStyle(selectedTab == tab ? theme.primary : .secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            Divider()

            // Tab content
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsTab()
                case .cli:
                    CLISettingsTab()
                case .sessions:
                    SessionSettingsTab()
                case .notifications:
                    NotificationSettingsTab()
                case .about:
                    AboutTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 500, maxWidth: 500, minHeight: 520)
        .onReceive(NotificationCenter.default.publisher(for: Self.openCLITabNotification)) { _ in
            selectedTab = .cli
        }
    }
}

struct GeneralSettingsTab: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var baseUrl = ""
    @State private var weekStartDay = "sunday"

    // MARK: - Danger Zone State

    @State private var showDeleteTodayAlert = false
    @State private var showDeleteRangeAlert = false
    @State private var showDeleteActivitiesAlert = false
    @State private var showDeleteTagsAlert = false
    @State private var showFactoryResetAlert = false

    @State private var bulkDeleteRange: BulkDeleteRange = .thisWeek
    @State private var pendingDeleteCount = 0

    var body: some View {
        @Bindable var theme = theme

        Form {
            Section("Week Start") {
                Picker("Start week on", selection: $weekStartDay) {
                    Text("Sunday").tag("sunday")
                    Text("Monday").tag("monday")
                }
                .onAppear { loadWeekStartDay() }
                .onChange(of: weekStartDay) {
                    Task {
                        try? await appState.service.setPreference(
                            key: PreferenceKey.weekStartDay,
                            value: weekStartDay
                        )
                    }
                }
            }

            Section("Appearance") {
                ForEach(ColorPalette.allCases, id: \.self) { palette in
                    PaletteRow(
                        palette: palette,
                        isSelected: theme.activePalette == palette,
                        colors: ThemeManager.previewColors(for: palette)
                    ) {
                        theme.activePalette = palette
                        Task {
                            try? await appState.service.setPreference(
                                key: PreferenceKey.colorPalette,
                                value: palette.rawValue
                            )
                        }
                    }
                }
            }

            Section("External ID") {
                TextField("Base URL", text: $baseUrl, prompt: Text("https://linear.app/team/issue/"))
                    .onAppear { loadBaseUrl() }
                    .onChange(of: baseUrl) {
                        Task {
                            try? await appState.service.setPreference(
                                key: PreferenceKey.externalIdBaseUrl,
                                value: baseUrl
                            )
                        }
                    }

                Text("Activity external IDs will be appended to this URL to create clickable links.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            dangerZoneSection
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Danger Zone

    private var dangerZoneSection: some View {
        Section {
            // Delete today's sessions
            Button(role: .destructive) {
                Task {
                    pendingDeleteCount = try await appState.service.countSessions(in: .today)
                    showDeleteTodayAlert = true
                }
            } label: {
                Label("Delete today's sessions", systemImage: "trash")
            }
            .alert("Delete Today's Sessions", isPresented: $showDeleteTodayAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task { await performDeleteSessions(in: .today) }
                }
            } message: {
                Text("This will permanently delete \(pendingDeleteCount) session(s) from today. This cannot be undone.")
            }

            // Bulk delete sessions by range
            HStack {
                Picker("Delete sessions from", selection: $bulkDeleteRange) {
                    Text("This Week").tag(BulkDeleteRange.thisWeek)
                    Text("This Month").tag(BulkDeleteRange.thisMonth)
                    Text("All Time").tag(BulkDeleteRange.allTime)
                }
                .frame(maxWidth: .infinity)

                Button(role: .destructive) {
                    Task {
                        pendingDeleteCount = try await appState.service.countSessions(in: bulkDeleteRange)
                        showDeleteRangeAlert = true
                    }
                } label: {
                    Text("Delete")
                }
            }
            .alert("Delete Sessions", isPresented: $showDeleteRangeAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task { await performDeleteSessions(in: bulkDeleteRange) }
                }
            } message: {
                Text("This will permanently delete \(pendingDeleteCount) session(s). Any active session will be cancelled. This cannot be undone.")
            }

            // Delete all activities
            Button(role: .destructive) {
                showDeleteActivitiesAlert = true
            } label: {
                Label("Delete all activities", systemImage: "tray.full")
            }
            .alert("Delete All Activities", isPresented: $showDeleteActivitiesAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive) {
                    Task { await performDeleteAllActivities() }
                }
            } message: {
                Text("This will delete all \(appState.allActivities.count) activities and their sessions. Any active session will be cancelled. This cannot be undone.")
            }

            // Delete all tags
            Button(role: .destructive) {
                showDeleteTagsAlert = true
            } label: {
                Label("Delete all tags", systemImage: "tag")
            }
            .alert("Delete All Tags", isPresented: $showDeleteTagsAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive) {
                    Task { await performDeleteAllTags() }
                }
            } message: {
                Text("This will delete all \(appState.allTags.count) tags. Activities will be kept but their tag associations removed.")
            }

            // Factory reset
            Button(role: .destructive) {
                showFactoryResetAlert = true
            } label: {
                Label("Factory reset", systemImage: "arrow.counterclockwise")
            }
            .alert("Factory Reset", isPresented: $showFactoryResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset Everything", role: .destructive) {
                    Task { await performFactoryReset() }
                }
            } message: {
                Text("This will delete ALL sessions, activities, tags, and preferences. Everything will be wiped. This cannot be undone.")
            }
        } header: {
            Label("Danger Zone", systemImage: "exclamationmark.triangle")
                .foregroundStyle(theme.alert)
        }
    }

    // MARK: - Danger Zone Actions

    private func performDeleteSessions(in range: BulkDeleteRange) async {
        do {
            _ = try await appState.service.deleteSessions(in: range)
            SoundManager.shared.play(.dip)
            await appState.refreshAll()
        } catch {
            appState.showError(error, context: "Could not delete sessions")
        }
    }

    private func performDeleteAllActivities() async {
        do {
            _ = try await appState.service.deleteAllActivities()
            SoundManager.shared.play(.dip)
            await appState.refreshAll()
        } catch {
            appState.showError(error, context: "Could not delete activities")
        }
    }

    private func performDeleteAllTags() async {
        do {
            _ = try await appState.service.deleteAllTags()
            SoundManager.shared.play(.dip)
            await appState.refreshAll()
        } catch {
            appState.showError(error, context: "Could not delete tags")
        }
    }

    private func performFactoryReset() async {
        do {
            try await appState.service.factoryReset()
            SoundManager.shared.play(.dip)
            await appState.refreshAll()
        } catch {
            appState.showError(error, context: "Could not perform factory reset")
        }
    }

    // MARK: - Helpers

    private func loadBaseUrl() {
        Task {
            baseUrl = try await appState.service.getPreference(key: PreferenceKey.externalIdBaseUrl) ?? ""
        }
    }

    private func loadWeekStartDay() {
        Task {
            weekStartDay = try await appState.service.getPreference(key: PreferenceKey.weekStartDay) ?? "sunday"
        }
    }

}

struct CLISettingsTab: View {
    @Environment(ThemeManager.self) private var theme
    @State private var cliInstallStatus: String?
    @State private var showCLIResult = false
    @State private var installedVersion: String?
    @State private var bundledVersion: String?
    @State private var isDetecting = true

    var body: some View {
        Form {
            Section("Install") {
                Button("Install CLI to /usr/local/bin") {
                    installCLI()
                }
                .alert("CLI Install", isPresented: $showCLIResult) {
                    Button("OK") {}
                } message: {
                    Text(cliInstallStatus ?? "")
                }

                Text("Copies the `present-cli` (\(Constants.cliVersion)) command-line tool so you can use it from Terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                cliVersionStatus
            }

            Section("What you can do") {
                VStack(alignment: .leading, spacing: 8) {
                    cliFeatureRow(icon: "play.fill", text: "Start, pause, and stop sessions")
                    cliFeatureRow(icon: "list.bullet", text: "Manage activities and tags")
                    cliFeatureRow(icon: "chart.bar.fill", text: "Export reports as CSV or JSON")
                    cliFeatureRow(icon: "magnifyingglass", text: "Search and filter session history")
                    cliFeatureRow(icon: "gearshape.fill", text: "Automate workflows with scripts")
                }
            }

            Section {
                Text("Run `present-cli --help` for a full list of commands.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await detectCLIVersions()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var cliVersionStatus: some View {
        if isDetecting {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking CLI…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let installed = installedVersion {
            if installed == bundledVersion {
                Text("Installed — v\(installed)")
                    .font(.caption)
                    .foregroundStyle(theme.success)
            } else {
                Text("Installed — v\(installed) (update available)")
                    .font(.caption)
                    .foregroundStyle(theme.warning)
            }
        } else {
            Text("CLI is not installed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func cliFeatureRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.callout)
        }
    }

    // MARK: - Helpers

    private func detectCLIVersions() async {
        isDetecting = true
        defer { isDetecting = false }

        // Get bundled version
        if let bundlePath = Bundle.main.path(forAuxiliaryExecutable: "present-cli") {
            bundledVersion = runVersionCommand(at: bundlePath)
        }

        // Get installed version
        installedVersion = runVersionCommand(at: "/usr/local/bin/present-cli")
    }

    private func runVersionCommand(at path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func installCLI() {
        guard let bundlePath = Bundle.main.path(forAuxiliaryExecutable: "present-cli") else {
            cliInstallStatus = "CLI binary not found in app bundle. Try reinstalling the app."
            showCLIResult = true
            return
        }

        let escapedPath = bundlePath.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        do shell script "cp \\\"\(escapedPath)\\\" /usr/local/bin/present-cli && chmod +x /usr/local/bin/present-cli" with administrator privileges
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error {
                let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                cliInstallStatus = "Installation failed: \(message)"
            } else {
                cliInstallStatus = "Installed! Run `present-cli --help` in Terminal to get started."
                Task {
                    await detectCLIVersions()
                }
            }
        } else {
            cliInstallStatus = "Failed to create install script."
        }
        showCLIResult = true
    }
}

struct SessionSettingsTab: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var defaultMinutes = 25
    @State private var longBreak = 15
    @State private var cycleLength = 4
    @State private var durationOptions: [RhythmOption] = Constants.defaultRhythmDurationOptions
    @State private var newFocusText = ""
    @State private var newBreakText = ""
    @State private var durationValidationError: String?
    @State private var defaultTimeboundMinutes = Constants.defaultTimeboundMinutes

    var body: some View {
        Form {
            Section {
                ForEach(durationOptions, id: \.self) { option in
                    HStack {
                        Text("\(option.focusMinutes) min focus / \(option.breakMinutes) min break")
                            .monospacedDigit()
                        Spacer()
                        Button {
                            removeDurationOption(option)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(theme.alert)
                        }
                        .buttonStyle(.plain)
                        .disabled(durationOptions.count <= 1)
                    }
                }

                if durationOptions.count < Constants.maxRhythmDurationOptions {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Focus", text: $newFocusText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                                .fixedSize()

                            Text("min  /")
                                .fixedSize()
                                .foregroundStyle(.secondary)

                            TextField("Break", text: $newBreakText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                                .fixedSize()
                                .onSubmit { addDurationOption() }

                            Text("min")
                                .fixedSize()
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button {
                                addDurationOption()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(theme.accent)
                            }
                            .buttonStyle(.plain)
                            .disabled(newFocusText.isEmpty || newBreakText.isEmpty)
                        }

                        if let error = durationValidationError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(theme.alert)
                        }
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rhythm Sessions")
                    Text("Timed focus cycles with short breaks, like a pomodoro timer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontWeight(.regular)
                        .textCase(.none)
                }
            } footer: {
                Text("Up to \(Constants.maxRhythmDurationOptions) focus/break pairs. Focus: \(Constants.rhythmDurationRange.lowerBound)\u{2013}\(Constants.rhythmDurationRange.upperBound) min, break: \(Constants.breakDurationRange.lowerBound)\u{2013}\(Constants.breakDurationRange.upperBound) min.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Default duration", selection: $defaultMinutes) {
                    ForEach(durationOptions, id: \.self) { option in
                        Text("\(option.focusMinutes) min (\(option.breakMinutes)m break)").tag(option.focusMinutes)
                    }
                }

                Stepper(value: $cycleLength, in: 2...8) {
                    HStack {
                        Text("Long break after")
                        Spacer()
                        Text("\(cycleLength) sessions")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Stepper(value: $longBreak, in: 5...60) {
                    HStack {
                        Text("Long break duration")
                        Spacer()
                        Text("\(longBreak) minutes")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            Section {
                Stepper(value: $defaultTimeboundMinutes, in: Constants.timeboundDurationRange) {
                    HStack {
                        Text("Default duration")
                        Spacer()
                        Text("\(defaultTimeboundMinutes) minutes")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Timebound Sessions")
                    Text("A hard stop timer. The session ends automatically when time is up.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontWeight(.regular)
                        .textCase(.none)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { loadSettings() }
        .onChange(of: defaultTimeboundMinutes) { saveSettings() }
        .onChange(of: defaultMinutes) { saveSettings() }
        .onChange(of: longBreak) { saveSettings() }
        .onChange(of: cycleLength) { saveSettings() }
    }

    // MARK: - Duration Option Actions

    private func addDurationOption() {
        durationValidationError = nil
        guard let focus = Int(newFocusText.trimmingCharacters(in: .whitespaces)) else {
            durationValidationError = "Enter focus minutes"
            return
        }
        guard let breakMins = Int(newBreakText.trimmingCharacters(in: .whitespaces)) else {
            durationValidationError = "Enter break minutes"
            return
        }
        guard Constants.rhythmDurationRange.contains(focus) else {
            durationValidationError = "Focus: \(Constants.rhythmDurationRange.lowerBound)\u{2013}\(Constants.rhythmDurationRange.upperBound)"
            return
        }
        guard Constants.breakDurationRange.contains(breakMins) else {
            durationValidationError = "Break: \(Constants.breakDurationRange.lowerBound)\u{2013}\(Constants.breakDurationRange.upperBound)"
            return
        }
        guard !durationOptions.contains(where: { $0.focusMinutes == focus }) else {
            durationValidationError = "Focus duration exists"
            return
        }
        let option = RhythmOption(focusMinutes: focus, breakMinutes: breakMins)
        durationOptions.append(option)
        durationOptions.sort { $0.focusMinutes < $1.focusMinutes }
        newFocusText = ""
        newBreakText = ""
        saveDurationOptions()
    }

    private func removeDurationOption(_ option: RhythmOption) {
        guard durationOptions.count > 1 else { return }
        durationOptions.removeAll { $0 == option }
        // If default is no longer in the list, reset it
        if !durationOptions.contains(where: { $0.focusMinutes == defaultMinutes }) {
            defaultMinutes = durationOptions.first?.focusMinutes ?? Constants.defaultRhythmMinutes
        }
        saveDurationOptions()
        saveSettings()
    }

    private func saveDurationOptions() {
        let serialized = PreferenceKey.serializeRhythmOptions(durationOptions)
        Task {
            try? await appState.service.setPreference(
                key: PreferenceKey.rhythmDurationOptions,
                value: serialized
            )
            await appState.refreshAll()
        }
    }

    // MARK: - Settings

    private func loadSettings() {
        Task {
            if let val = try? await appState.service.getPreference(key: PreferenceKey.defaultTimeboundMinutes) {
                defaultTimeboundMinutes = Int(val) ?? Constants.defaultTimeboundMinutes
            }
            if let val = try? await appState.service.getPreference(key: PreferenceKey.rhythmDurationOptions) {
                let parsed = PreferenceKey.parseRhythmOptions(val)
                if !parsed.isEmpty {
                    durationOptions = parsed
                }
            }
            if let val = try? await appState.service.getPreference(key: PreferenceKey.defaultRhythmMinutes) {
                defaultMinutes = Int(val) ?? 25
            }
            // Ensure default is in the options list
            if !durationOptions.contains(where: { $0.focusMinutes == defaultMinutes }) {
                defaultMinutes = durationOptions.first?.focusMinutes ?? Constants.defaultRhythmMinutes
            }
            if let val = try? await appState.service.getPreference(key: PreferenceKey.longBreakMinutes) {
                longBreak = Int(val) ?? 15
            }
            if let val = try? await appState.service.getPreference(key: PreferenceKey.rhythmCycleLength) {
                cycleLength = Int(val) ?? 4
            }
        }
    }

    private func saveSettings() {
        Task {
            try? await appState.service.setPreference(key: PreferenceKey.defaultTimeboundMinutes, value: "\(defaultTimeboundMinutes)")
            try? await appState.service.setPreference(key: PreferenceKey.defaultRhythmMinutes, value: "\(defaultMinutes)")
            try? await appState.service.setPreference(key: PreferenceKey.longBreakMinutes, value: "\(longBreak)")
            try? await appState.service.setPreference(key: PreferenceKey.rhythmCycleLength, value: "\(cycleLength)")
        }
    }
}

struct AboutTab: View {
    @Environment(ThemeManager.self) private var theme
    @State private var installedCLIVersion: String?
    @State private var isDetectingCLI = true

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var cliIsOutdated: Bool {
        guard let installed = installedCLIVersion else { return false }
        return installed != Constants.cliVersion
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("Present")
                .font(.title.bold())

            VStack(spacing: 4) {
                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                cliVersionLine
            }

            Text("Developed by Terri Ann Swallow")
                .font(.body)

            VStack(spacing: 8) {
                Link("GitHub Repository", destination: URL(string: "https://github.com/terriann/present")!)
                    .font(.callout)
                    .foregroundStyle(theme.accent)

                Link("Sound effects by Epidemic Sound", destination: URL(string: "https://www.epidemicsound.com/sound-effects/playlists/interfaceessentials/")!)
                    .font(.callout)
                    .foregroundStyle(theme.accent)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
        .task {
            await detectInstalledCLI()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var cliVersionLine: some View {
        if !isDetectingCLI && cliIsOutdated {
            Button {
                NotificationCenter.default.post(name: SettingsView.openCLITabNotification, object: nil)
            } label: {
                Text("CLI: v\(Constants.cliVersion) — Update Available")
                    .font(.caption)
                    .foregroundStyle(theme.primary)
            }
            .buttonStyle(.plain)
        } else {
            Text("CLI: v\(Constants.cliVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func detectInstalledCLI() async {
        isDetectingCLI = true
        defer { isDetectingCLI = false }

        let path = "/usr/local/bin/present-cli"
        guard FileManager.default.fileExists(atPath: path) else {
            installedCLIVersion = nil
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            if let data = try pipe.fileHandleForReading.readToEnd(),
               let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                installedCLIVersion = output
            }
        } catch {
            installedCLIVersion = nil
        }
    }
}

struct NotificationSettingsTab: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var soundEnabled = true

    var body: some View {
        Form {
            Section("Sound") {
                Toggle("Play sounds", isOn: $soundEnabled)
                    .toggleStyle(ThemedToggleStyle(tintColor: theme.accent))
                    .onChange(of: soundEnabled) {
                        SoundManager.shared.isEnabled = soundEnabled
                        Task {
                            try? await appState.service.setPreference(
                                key: PreferenceKey.soundEffectsEnabled,
                                value: soundEnabled ? "1" : "0"
                            )
                        }
                    }

                Text("In-app effects and notification sounds for session events, cancellation, and break suggestions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            Task {
                if let val = try? await appState.service.getPreference(key: PreferenceKey.soundEffectsEnabled) {
                    soundEnabled = val == "1"
                }
            }
        }
    }
}

// MARK: - Palette Row

private struct PaletteRow: View {
    @Environment(ThemeManager.self) private var theme

    let palette: ColorPalette
    let isSelected: Bool
    let colors: [Color]
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? colors.first ?? theme.accent : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 6) {
                    Text(palette.displayName)
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)

                    HStack(spacing: 0) {
                        ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                            Rectangle()
                                .fill(color)
                                .frame(height: 20)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .frame(maxWidth: 200)
                }

                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.secondary.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAdaptiveAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}
