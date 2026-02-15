import SwiftUI
import PresentCore

@main
struct PresentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        let _ = startStatusItemMenu()

        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            MenuBarLabelView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        Window("Present", id: "main") {
            ContentView()
                .environment(appState)
                .onAppear {
                    appDelegate.appState = appState
                    appState.showDockIcon(true)
                }
                .onDisappear { appState.showDockIcon(false) }
        }
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }

    private func startStatusItemMenu() {
        guard appDelegate.statusItemMenuManager == nil else { return }
        let manager = StatusItemMenuManager(appState: appState)
        appDelegate.statusItemMenuManager = manager
        manager.start()
    }
}

/// Menu bar icon + timer label. Always visible, so it can observe notifications
/// from `StatusItemMenuManager` and bridge them to SwiftUI environment actions.
private struct MenuBarLabelView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: appState.menuBarIcon)
            if let timerText = appState.menuBarTimerText {
                Text(timerText)
                    .monospacedDigit()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: StatusItemMenuManager.openMainWindowNotification)) { _ in
            openWindow(id: "main")
            // Activate after the window is created so it appears in front.
            DispatchQueue.main.async {
                NSApplication.shared.activate()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: StatusItemMenuManager.openSettingsNotification)) { _ in
            openSettings()
            DispatchQueue.main.async {
                NSApplication.shared.activate()
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?
    var statusItemMenuManager: StatusItemMenuManager?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appState, appState.isSessionActive else {
            return .terminateNow
        }

        Task { @MainActor in
            await appState.stopSession()
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
