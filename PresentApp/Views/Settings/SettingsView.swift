import SwiftUI
import PresentCore

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .environment(appState)
                .tabItem { Label("General", systemImage: "gear") }

            RhythmSettingsTab()
                .environment(appState)
                .tabItem { Label("Rhythm", systemImage: "timer") }

            NotificationSettingsTab()
                .environment(appState)
                .tabItem { Label("Notifications", systemImage: "bell") }
        }
        .frame(width: 450, height: 300)
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

    var body: some View {
        Form {
            Section("Rhythm Session Defaults") {
                Picker("Default duration", selection: $defaultMinutes) {
                    Text("25 minutes").tag(25)
                    Text("30 minutes").tag(30)
                    Text("45 minutes").tag(45)
                }

                Stepper("Short break: \(shortBreak) min", value: $shortBreak, in: 1...30)
                Stepper("Long break: \(longBreak) min", value: $longBreak, in: 5...60)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { loadSettings() }
        .onChange(of: defaultMinutes) { saveSettings() }
        .onChange(of: shortBreak) { saveSettings() }
        .onChange(of: longBreak) { saveSettings() }
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
        }
    }

    private func saveSettings() {
        Task {
            try? await appState.service.setPreference(key: PreferenceKey.defaultRhythmMinutes, value: "\(defaultMinutes)")
            try? await appState.service.setPreference(key: PreferenceKey.shortBreakMinutes, value: "\(shortBreak)")
            try? await appState.service.setPreference(key: PreferenceKey.longBreakMinutes, value: "\(longBreak)")
        }
    }
}

struct NotificationSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var soundEnabled = true

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
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            Task {
                if let val = try? await appState.service.getPreference(key: PreferenceKey.notificationSound) {
                    soundEnabled = val == "1"
                }
            }
        }
    }
}
