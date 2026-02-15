import SwiftUI
import PresentCore

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab = SettingsTab.general

    private enum SettingsTab: Hashable {
        case general, rhythm, notifications, about
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .environment(appState)
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsTab.general)

            RhythmSettingsTab()
                .environment(appState)
                .tabItem { Label("Rhythm", systemImage: "timer") }
                .tag(SettingsTab.rhythm)

            NotificationSettingsTab()
                .environment(appState)
                .tabItem { Label("Notifications", systemImage: "bell") }
                .tag(SettingsTab.notifications)

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 450, height: 300)
        .onAppear { selectedTab = .general }
    }
}

struct GeneralSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var baseUrl = ""

    var body: some View {
        Form {
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

            Section("CLI") {
                Button("Install CLI to /usr/local/bin") {
                    installCLI()
                }

                Text("Copies the `present` command-line tool so you can use it from Terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func loadBaseUrl() {
        Task {
            baseUrl = try await appState.service.getPreference(key: PreferenceKey.externalIdBaseUrl) ?? ""
        }
    }

    private func installCLI() {
        guard let bundlePath = Bundle.main.path(forAuxiliaryExecutable: "present") else {
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cp")
        process.arguments = [bundlePath, "/usr/local/bin/present"]
        try? process.run()
        process.waitUntilExit()
    }
}

struct RhythmSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var defaultMinutes = 25
    @State private var shortBreak = 5
    @State private var longBreak = 15
    @State private var cycleLength = 4

    var body: some View {
        Form {
            Section {
                Picker("Default duration", selection: $defaultMinutes) {
                    Text("25 minutes").tag(25)
                    Text("30 minutes").tag(30)
                    Text("45 minutes").tag(45)
                }

                Stepper(value: $shortBreak, in: 1...30) {
                    HStack {
                        Text("Short break")
                        Spacer()
                        Text("\(shortBreak) minutes")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Stepper(value: $longBreak, in: 5...60) {
                    HStack {
                        Text("Long break")
                        Spacer()
                        Text("\(longBreak) minutes")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
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
            } header: {
                Text("Rhythm Session Defaults")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { loadSettings() }
        .onChange(of: defaultMinutes) { saveSettings() }
        .onChange(of: shortBreak) { saveSettings() }
        .onChange(of: longBreak) { saveSettings() }
        .onChange(of: cycleLength) { saveSettings() }
    }

    private func loadSettings() {
        Task {
            if let val = try? await appState.service.getPreference(key: PreferenceKey.defaultRhythmMinutes) {
                defaultMinutes = Int(val) ?? 25
            }
            if let val = try? await appState.service.getPreference(key: PreferenceKey.shortBreakMinutes) {
                shortBreak = Int(val) ?? 5
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
            try? await appState.service.setPreference(key: PreferenceKey.defaultRhythmMinutes, value: "\(defaultMinutes)")
            try? await appState.service.setPreference(key: PreferenceKey.shortBreakMinutes, value: "\(shortBreak)")
            try? await appState.service.setPreference(key: PreferenceKey.longBreakMinutes, value: "\(longBreak)")
            try? await appState.service.setPreference(key: PreferenceKey.rhythmCycleLength, value: "\(cycleLength)")
        }
    }
}

struct AboutTab: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "clock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Present")
                .font(.title.bold())

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Developed by Terri Ann Swallow")
                .font(.body)

            VStack(spacing: 8) {
                Link("GitHub Repository", destination: URL(string: "https://github.com/terriann/present")!)
                    .font(.callout)

                Link("Sound effects by Epidemic Sound", destination: URL(string: "https://www.epidemicsound.com/sound-effects/playlists/interfaceessentials/")!)
                    .font(.callout)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

struct NotificationSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var soundEnabled = true
    @State private var soundEffectsEnabled = true

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Play sound on timer completion", isOn: $soundEnabled)
                    .onChange(of: soundEnabled) {
                        Task {
                            try? await appState.service.setPreference(
                                key: PreferenceKey.notificationSound,
                                value: soundEnabled ? "1" : "0"
                            )
                        }
                    }
            }

            Section("Sound Effects") {
                Toggle("Play UI sound effects", isOn: $soundEffectsEnabled)
                    .onChange(of: soundEffectsEnabled) {
                        SoundManager.shared.isEnabled = soundEffectsEnabled
                        Task {
                            try? await appState.service.setPreference(
                                key: PreferenceKey.soundEffectsEnabled,
                                value: soundEffectsEnabled ? "1" : "0"
                            )
                        }
                    }

                Text("Sounds for session completion, cancellation, and break suggestions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            Task {
                if let val = try? await appState.service.getPreference(key: PreferenceKey.notificationSound) {
                    soundEnabled = val == "1"
                }
                if let val = try? await appState.service.getPreference(key: PreferenceKey.soundEffectsEnabled) {
                    soundEffectsEnabled = val == "1"
                }
            }
        }
    }
}
