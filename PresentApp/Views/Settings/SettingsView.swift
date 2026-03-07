import SwiftUI
import ServiceManagement
import PresentCore

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var selectedTab = SettingsTab.general

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
                        .padding(.vertical, Constants.spacingCompact)
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
            .padding(.horizontal, Constants.spacingCard)
            .padding(.top, 10)
            .padding(.bottom, Constants.spacingTight)

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
        .onChange(of: appState.pendingSettingsTab) { _, tab in
            guard let tab else { return }
            selectedTab = tab
            appState.pendingSettingsTab = nil
        }
    }
}

struct GeneralSettingsTab: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var launchOnLogin = SMAppService.mainApp.status == .enabled
    @State private var weekStartDay = "sunday"
    @State private var appearanceMode: AppearanceMode = .system

    // MARK: - Data Management State

    @State private var showDeleteRangeAlert = false
    @State private var bulkDeleteRange: BulkDeleteRange = .today
    @State private var pendingDeleteCount = 0

    var body: some View {
        @Bindable var theme = theme

        Form {
            Section {
                Toggle("Start Present when you log in", isOn: $launchOnLogin)
                    .toggleStyle(ThemedToggleStyle(tintColor: theme.accent))
                    .onChange(of: launchOnLogin) {
                        do {
                            if launchOnLogin {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchOnLogin = SMAppService.mainApp.status == .enabled
                            appState.showError(error, context: "Could not update login item", scene: .settings)
                        }
                    }

                Text("Present will start silently in the menu bar when you log in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Launch on Login")
            }

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
                HStack(spacing: 0) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Button {
                            appearanceMode = mode
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: mode.iconName)
                                Text(mode.displayName)
                            }
                            .font(.subheadline)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background {
                                if appearanceMode == mode {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                        .shadow(color: .black.opacity(0.1), radius: 1, y: 0.5)
                                        .padding(1)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(appearanceMode == mode ? .primary : .secondary)
                    }
                }
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(nsColor: .separatorColor).opacity(0.2))
                )
                .onAppear { loadAppearanceMode() }
                .onChange(of: appearanceMode) {
                    theme.appearanceMode = appearanceMode
                    Task {
                        try? await appState.service.setPreference(
                            key: PreferenceKey.appearanceMode,
                            value: appearanceMode.rawValue
                        )
                    }
                }
            }

            Section("Color Palette") {
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

            dangerZoneSection
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Data Management

    private var dangerZoneSection: some View {
        Section {
            HStack {
                Picker("Delete sessions from", selection: $bulkDeleteRange) {
                    Text("Today").tag(BulkDeleteRange.today)
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

            // CLI callout
            HStack(spacing: Constants.spacingCompact) {
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Need more control? Use `present-cli` for advanced delete operations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open CLI Setup") {
                    appState.pendingSettingsTab = .cli
                }
                .font(.caption)
                .foregroundStyle(theme.accent)
                .buttonStyle(.plain)
            }
        } header: {
            Label("Proceed With Caution", systemImage: "exclamationmark.triangle")
                .foregroundStyle(theme.alert)
        }
    }

    // MARK: - Actions

    private func performDeleteSessions(in range: BulkDeleteRange) async {
        do {
            _ = try await appState.service.deleteSessions(in: range)
            SoundManager.shared.play(.dip)
            await appState.refreshAll()
        } catch {
            appState.showError(error, context: "Could not delete sessions", scene: .settings)
        }
    }

    // MARK: - Helpers

    private func loadWeekStartDay() {
        Task {
            weekStartDay = try await appState.service.getPreference(key: PreferenceKey.weekStartDay) ?? "sunday"
        }
    }

    private func loadAppearanceMode() {
        Task {
            if let value = try? await appState.service.getPreference(key: PreferenceKey.appearanceMode),
               let mode = AppearanceMode(rawValue: value) {
                appearanceMode = mode
            }
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
                HStack(spacing: Constants.spacingCompact) {
                    Button("Install present-cli v\(Constants.appVersion)") {
                        installCLI()
                    }
                    .alert("CLI Install", isPresented: $showCLIResult) {
                        Button("OK") {}
                    } message: {
                        Text(cliInstallStatus ?? "")
                    }

                    cliVersionBadge
                    Spacer()
                }

                Text("`present-cli --help` for a full list of commands.\n`present-cli --experimental-dump-help` to inform use in agentic AI.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
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
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await detectCLIVersions()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var cliVersionBadge: some View {
        if !isDetecting, let installed = installedVersion {
            if installed == bundledVersion {
                Label("v\(installed)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(theme.success)
            } else {
                Label("v\(installed)", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(theme.warning)
            }
        }
        // Not installed or still detecting: no indicator shown
    }

    private func cliFeatureRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
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
        do shell script "cp \\\"\(escapedPath)\\\" /usr/local/bin/present-cli && chmod +x /usr/local/bin/present-cli" with prompt "Present needs your password to install present-cli into /usr/local/bin." with administrator privileges
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
    @FocusState private var focusedDurationField: DurationField?

    private enum DurationField { case focus, breakMinutes }

    var body: some View {
        Form {
            Section {
                ForEach(durationOptions, id: \.self) { option in
                    HStack {
                        Text(option.settingsLabel)
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
                        .accessibilityLabel("Remove \(option.settingsLabel)")
                        .help("Remove rhythm option")
                    }
                }

                if durationOptions.count < Constants.maxRhythmDurationOptions {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Focus", text: $newFocusText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                                .fixedSize()
                                .focused($focusedDurationField, equals: .focus)
                                .onSubmit { focusedDurationField = .breakMinutes }

                            Text("min  /")
                                .fixedSize()
                                .foregroundStyle(.secondary)

                            TextField("Break", text: $newBreakText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                                .fixedSize()
                                .focused($focusedDurationField, equals: .breakMinutes)
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
                            .onKeyPress(keys: [.return, .space]) { _ in
                                guard !newFocusText.isEmpty && !newBreakText.isEmpty else { return .ignored }
                                addDurationOption()
                                return .handled
                            }
                            .accessibilityLabel("Add rhythm option")
                            .help("Add rhythm option")
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
                        Text(option.settingsLabel).tag(option.focusMinutes)
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

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("Present")
                .font(.title.bold())

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

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
            .padding(.vertical, Constants.spacingTight)
            .padding(.horizontal, Constants.spacingCompact)
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
