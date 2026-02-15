import SwiftUI
import PresentCore

@main
struct PresentApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appState.menuBarIcon)
                if let timerText = appState.menuBarTimerText {
                    Text(timerText)
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window("Present", id: "main") {
            ContentView()
                .environment(appState)
                .onAppear { appState.showDockIcon(true) }
                .onDisappear { appState.showDockIcon(false) }
        }
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
